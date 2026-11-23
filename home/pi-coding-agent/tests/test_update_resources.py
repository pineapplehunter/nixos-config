"""Exercise the updater in disposable homes without updating real packages."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import unquote, urlsplit


UPDATER = Path(__file__).resolve().parents[1] / "pi-update.py"


class UpdateResources(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / "home"
        self.repo = self.root / "source"
        self.repo.mkdir()
        self.agent = self.home / ".pi/agent"
        self.agent.mkdir(parents=True)
        self.settings = self.agent / "settings.json"
        self.installed = self.agent / "npm/node_modules/pi-customizations"
        self.legacy = self.home / ".pi/customizations"
        self.calls = self.root / "calls.jsonl"
        fake_pi = self.root / "pi"
        fake_pi.write_text(
            f"#!{sys.executable}\n"
            "import json, os, shutil, sys, tarfile\n"
            "from pathlib import Path\n"
            "from urllib.parse import unquote, urlsplit\n"
            "agent = Path(os.environ['PI_CODING_AGENT_DIR'])\n"
            f"with open({str(self.calls)!r}, 'a') as output:\n"
            " output.write(json.dumps([sys.argv[1:], str(agent),\n"
            "   os.environ.get('npm_config_ignore_scripts')]) + '\\n')\n"
            "if sys.argv[1] == 'install':\n"
            " code = int(os.environ.get('FAKE_INSTALL_EXIT', '0'))\n"
            " if code: sys.exit(code)\n"
            " source = sys.argv[2]\n"
            " archive = Path(unquote(urlsplit(source.split('@', 1)[1]).path))\n"
            " installed = agent / 'npm/node_modules/pi-customizations'\n"
            " if installed.exists(): shutil.rmtree(installed)\n"
            " installed.mkdir(parents=True)\n"
            " with tarfile.open(archive) as package:\n"
            "  package.extractall(installed, filter='data')\n"
            " settings = agent / 'settings.json'\n"
            " data = json.loads(settings.read_text()) if settings.exists() else {}\n"
            " packages = data.get('packages', [])\n"
            " data['packages'] = [p for p in packages if not (\n"
            "  isinstance(p, str) and p.startswith('npm:pi-customizations@'))]\n"
            " data['packages'].append(source)\n"
            " settings.write_text(json.dumps(data))\n"
            " sys.exit(0)\n"
            "sys.exit(int(os.environ.get('FAKE_PI_EXIT', '0')))\n"
        )
        fake_pi.chmod(0o755)
        self.npm_calls = self.root / "npm-calls.jsonl"
        fake_npm = self.root / "npm"
        fake_npm.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys, tarfile\n"
            "from pathlib import Path\n"
            f"with open({str(self.npm_calls)!r}, 'a') as output:\n"
            " output.write(json.dumps([sys.argv[1:], os.getcwd()]) + '\\n')\n"
            "assert sys.argv[1] == 'pack'\n"
            "archive = Path(sys.argv[-1]) / 'prototype.tgz'\n"
            "with tarfile.open(archive, 'w:gz') as package:\n"
            " for path in Path.cwd().iterdir(): package.add(path, arcname=path.name)\n"
            "print(json.dumps([{'filename': archive.name}]))\n"
        )
        fake_npm.chmod(0o755)
        self.environment = {
            **os.environ, "HOME": str(self.home), "PI_UPDATE_PI": str(fake_pi),
            "PATH": f"{self.root}{os.pathsep}{os.environ['PATH']}",
        }
        (self.repo / "package.json").write_text(
            '{"name":"pi-customizations","dependencies":{"example":"1.0.0"}}'
        )
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

    def pi_calls(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def current_source(self):
        (source,) = [p for p in self.read_settings()["packages"]
                     if isinstance(p, str) and p.startswith("npm:pi-customizations@")]
        return source

    def archive(self):
        return Path(unquote(urlsplit(self.current_source().split("@", 1)[1]).path))

    def test_migrates_snapshot_without_touching_unrelated_state(self):
        filtered = {"source": "npm:filtered@1.0.0", "skills": []}
        old_snapshot = self.legacy / "package"
        old_snapshot.mkdir(parents=True)
        (self.legacy / "previous").mkdir()
        (self.legacy / "unrelated").touch()
        (self.legacy / "managed-packages.json").write_text(json.dumps({
            "agent": [str(old_snapshot), "npm:managed"],
        }))
        self.settings.write_text(json.dumps({
            "theme": "dark", "packages": ["npm:manual", filtered, "npm:managed",
                {"source": "../customizations/package", "skills": []}],
        }))
        auth = self.agent / "auth.json"
        auth.write_text("do not modify")
        old_instructions = self.root / "old-AGENTS.md"
        old_instructions.write_text("old")
        (self.agent / "AGENTS.md").symlink_to(old_instructions)
        self.local()
        self.assertEqual(self.read_settings(), {
            "theme": "dark", "packages": ["npm:manual", filtered,
                self.current_source(), "npm:managed"],
        })
        self.assertFalse(old_snapshot.exists())
        self.assertFalse((self.legacy / "previous").exists())
        self.assertTrue((self.legacy / "unrelated").is_file())
        self.assertEqual(auth.read_text(), "do not modify")
        self.assertEqual(old_instructions.read_text(), "old")
        self.assertFalse((self.agent / "AGENTS.md").is_symlink())
        self.packages([])
        self.local()
        self.assertIn(filtered, self.read_settings()["packages"])
        self.assertNotIn("npm:managed", self.read_settings()["packages"])

    def test_preexisting_manual_declaration_does_not_become_owned(self):
        self.settings.write_text('{"packages":["npm:managed"]}')
        self.local()
        self.packages([])
        self.local()
        self.assertIn("npm:managed", self.read_settings()["packages"])
        self.assertNotIn("npm:filtered", self.read_settings()["packages"])

    def test_local_packs_working_tree_and_uses_canonical_profile(self):
        self.environment["PI_CODING_AGENT_DIR"] = str(self.home / "custom")
        self.local()
        archive = self.archive()
        self.assertEqual(self.pi_calls(), [
            [["install", self.current_source(), "--no-approve"], str(self.agent), "true"],
            [["update", "--extensions", "--no-approve"], str(self.agent), None],
        ])
        args, cwd = json.loads(self.npm_calls.read_text())
        self.assertEqual(args, ["pack", "--json", "--ignore-scripts",
                                "--pack-destination", str(archive.parent)])
        self.assertFalse(Path(cwd).exists())
        self.assertTrue(archive.is_file())
        self.assertFalse(self.legacy.exists())
        self.assertFalse((self.home / "custom").exists())
        self.assertFalse((self.repo / "node_modules").exists())
        (self.repo / "extensions/tool.ts").write_text("uncommitted change\n")
        self.local()
        self.assertEqual((self.installed / "extensions/tool.ts").read_text(),
                         "uncommitted change\n")
        self.assertNotEqual(archive, self.archive())
        self.assertFalse(archive.exists())

    def test_invalid_source_does_not_call_pi(self):
        (self.repo / "settings.json").write_text('{"defaultModel":"not-managed"}')
        self.local(success=False)
        self.assertFalse(self.calls.exists())

    def test_failed_install_leaves_previous_archive_and_legacy_snapshot(self):
        self.local()
        archive = self.archive()
        snapshot = self.legacy / "package"
        snapshot.mkdir(parents=True)
        self.environment["FAKE_INSTALL_EXIT"] = "7"
        self.local(success=False)
        self.assertEqual(self.archive(), archive)
        self.assertTrue(archive.is_file())
        self.assertTrue(snapshot.is_dir())
        self.assertEqual(len(list(archive.parent.parent.iterdir())), 1)

    def test_external_failure_is_nonzero_and_retryable(self):
        snapshot = self.legacy / "package"
        snapshot.mkdir(parents=True)
        self.environment["FAKE_PI_EXIT"] = "7"
        self.local(success=False)
        self.assertTrue(self.archive().is_file())
        self.assertTrue(snapshot.is_dir())
        del self.environment["FAKE_PI_EXIT"]
        self.local()
        self.assertFalse(snapshot.exists())
        self.assertEqual(self.read_settings()["packages"].count("npm:managed"), 1)

    def test_remote_mode_installs_tarball_from_git_checkout(self):
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.repo)], check=True)
        subprocess.run(["git", "-C", str(self.repo), "add", "."], check=True)
        subprocess.run([
            "git", "-C", str(self.repo), "-c", "user.name=Updater Test",
            "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false",
            "commit", "-qm", "test fixture",
        ], check=True)
        (self.repo / "extensions/tool.ts").write_text("not committed\n")
        self.update("--repo", self.repo.as_uri())
        self.assertEqual((self.installed / "extensions/tool.ts").read_text(), "initial\n")
        self.assertFalse((self.installed / ".git").exists())
        self.assertEqual(self.pi_calls()[0][0][0], "install")


if __name__ == "__main__":
    unittest.main()
