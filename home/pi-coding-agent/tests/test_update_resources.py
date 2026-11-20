"""Exercise the updater in disposable homes without updating real packages."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


UPDATER = Path(__file__).resolve().parents[1] / "pi-update.py"


class UpdateResources(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.repo = self.root / "source"
        self.repo.mkdir()
        self.settings = self.home / ".pi/agent/settings.json"
        self.settings.parent.mkdir(parents=True)
        self.snapshot = self.home / ".pi/customizations/package"
        self.calls = self.root / "calls.jsonl"
        self.fake_pi = self.root / "pi"
        self.fake_pi.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            f"with open({str(self.calls)!r}, 'a') as output:\n"
            " output.write(json.dumps([sys.argv[1:], "
            "os.environ['PI_CODING_AGENT_DIR'], os.getcwd()]) + '\\n')\n"
            "sys.exit(int(os.environ.get('FAKE_PI_EXIT', '0')))\n"
        )
        self.fake_pi.chmod(0o755)
        self.environment = {
            **os.environ, "HOME": str(self.home),
            "PI_UPDATE_PI": str(self.fake_pi),
        }
        (self.repo / "package.json").write_text('{"name":"pi-customizations"}')
        (self.repo / "AGENTS.md").write_text("Shared instructions\n")
        (self.repo / "extensions").mkdir()
        (self.repo / "extensions/tool.ts").write_text("initial\n")
        self.packages(["npm:managed", "npm:filtered"])

    def packages(self, entries):
        (self.repo / "settings.json").write_text(json.dumps({"packages": entries}))

    def update(self, *arguments, success=True):
        result = subprocess.run(
            [sys.executable, str(UPDATER), *arguments],
            env=self.environment, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def local(self, **kwargs):
        return self.update("--local", str(self.repo), **kwargs)

    def read_settings(self):
        return json.loads(self.settings.read_text())

    def test_copies_and_reconciles_without_touching_unrelated_state(self):
        filtered = {"source": "npm:filtered@1.0.0", "skills": []}
        self.settings.write_text(json.dumps({
            "theme": "dark", "packages": ["npm:manual", filtered, "npm:managed",
                "/nix/store/old-pineapplehunter", "/nix/store/old-anthropic-skills"],
        }))
        auth = self.settings.with_name("auth.json")
        auth.write_text("do not modify")
        manual = self.settings.parent / "skills/manual/SKILL.md"
        manual.parent.mkdir(parents=True)
        manual.write_text("user skill")
        old_instructions = self.root / "old-AGENTS.md"
        old_instructions.write_text("old")
        self.settings.with_name("AGENTS.md").symlink_to(old_instructions)
        self.local()
        self.assertEqual(self.read_settings(), {
            "theme": "dark", "packages": ["npm:manual", filtered,
                "npm:managed", str(self.snapshot)],
        })
        self.assertEqual(auth.read_text(), "do not modify")
        self.assertEqual(manual.read_text(), "user skill")
        self.assertEqual(old_instructions.read_text(), "old")
        self.assertFalse(self.settings.with_name("AGENTS.md").is_symlink())
        self.assertEqual((self.snapshot / "extensions/tool.ts").read_text(), "initial\n")
        (self.repo / "extensions/tool.ts").unlink()
        self.packages([])
        self.local()
        self.assertFalse((self.snapshot / "extensions/tool.ts").exists())
        self.assertIn(filtered, self.read_settings()["packages"])
        self.assertNotIn("npm:managed", self.read_settings()["packages"])
        self.assertEqual(manual.read_text(), "user skill")
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0][0], ["update", "--extensions", "--no-approve"])
        self.assertEqual(calls[0][1], str(self.settings.parent))

    def test_preexisting_manual_declaration_does_not_become_owned(self):
        self.settings.write_text('{"packages":["npm:managed"]}')
        self.local()
        self.packages([])
        self.local()
        self.assertIn("npm:managed", self.read_settings()["packages"])
        self.assertNotIn("npm:filtered", self.read_settings()["packages"])

    def test_uses_canonical_agent_directory(self):
        self.environment["PI_CODING_AGENT_DIR"] = str(self.home / "custom")
        self.local()
        self.assertFalse((self.home / "custom").exists())
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1], str(self.settings.parent))

    def test_invalid_source_preserves_installed_resources(self):
        self.local()
        (self.repo / "settings.json").write_text('{"defaultModel":"not-managed"}')
        self.local(success=False)
        self.assertEqual((self.snapshot / "extensions/tool.ts").read_text(), "initial\n")
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)

    def test_external_failure_is_nonzero_and_retryable(self):
        self.environment["FAKE_PI_EXIT"] = "7"
        self.local(success=False)
        self.assertTrue(self.snapshot.is_dir())
        del self.environment["FAKE_PI_EXIT"]
        self.local()
        self.assertEqual(self.read_settings()["packages"].count("npm:managed"), 1)

    def test_remote_mode_copies_a_git_checkout(self):
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.repo)], check=True)
        subprocess.run(["git", "-C", str(self.repo), "add", "."], check=True)
        subprocess.run([
            "git", "-C", str(self.repo), "-c", "user.name=Updater Test",
            "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false",
            "commit", "-qm", "test fixture",
        ], check=True)
        self.update("--repo", self.repo.as_uri())
        self.assertTrue((self.snapshot / "extensions/tool.ts").is_file())
        self.assertFalse((self.snapshot / ".git").exists())
        self.assertFalse((self.snapshot / "extensions/tool.ts").is_symlink())


if __name__ == "__main__":
    unittest.main()
