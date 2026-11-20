import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import stat
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "pi-profile-cutover.py"
migrate = runpy.run_path(str(SCRIPT))["migrate"]


class ProfileCutoverTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.home = Path(directory.name)
        self.pi = self.home / ".pi"
        for name in ("agent", "agent-work", "agent-auto"):
            (self.pi / name).mkdir(parents=True)

    def settings(self, profile, value):
        path = self.pi / profile / "settings.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def session(self, profile, path, id_, text):
        path = self.pi / profile / "sessions" / path
        path.parent.mkdir(parents=True, exist_ok=True)
        entries = [
            {"type": "session", "version": 3, "id": id_, "cwd": "/fixture"},
            {"type": "message", "message": {"role": "user", "content": text}},
        ]
        path.write_text("".join(json.dumps(entry) + "\n" for entry in entries), encoding="utf-8")
        return path

    def run_migration(self, stage=False):
        with contextlib.redirect_stdout(io.StringIO()) as buf:
            migrate(self.home, stage_changes=stage)
        return buf.getvalue()

    def snapshot(self):
        return {
            p.relative_to(self.pi): (p.read_bytes(), p.stat().st_mtime_ns)
            for p in self.pi.rglob("*") if p.is_file() and not p.is_symlink()
        }

    def test_merge_conflicts_dedup_and_private_staging(self):
        self.settings("agent", {"theme": "dark", "terminal": {"showImages": False}, "defaultProvider": "kept"})
        self.settings("agent-work", {
            "theme": "light", "terminal": {"showImages": True, "imageWidthCells": 42},
            "quietStartup": "header", "editorPaddingX": 2, "externalEditor": "mock-private",
            "httpProxy": "mock-private", "defaultProvider": "codex-old", "defaultModel": "mock-private",
            "thinkingBudgets": {"mock-private": 1}, "defaultProjectTrust": "always",
        })
        self.settings("agent-auto", {
            "quietStartup": False, "editorPaddingX": 2, "terminal": {"hyperlinks": False},
            "outputPad": True, "defaultThinkingLevel": "high", "theme": "mock-private",
        })
        (self.pi / "agent-auto" / "auth.json").write_text("mock-private", encoding="utf-8")
        (self.pi / "agent-auto" / "trust.json").write_text("mock-private", encoding="utf-8")
        (self.pi / "agent-auto" / "npm").mkdir()

        self.session("agent", "shared.jsonl", "shared", "mock-private")
        self.session("agent-work", "--fixture--/duplicate.jsonl", "shared", "mock-private")
        self.session("agent-auto", "diverged.jsonl", "shared", "diverged")
        self.session("agent-auto", "shared.jsonl", "different-id", "path is occupied")
        work = self.session("agent-work", "--fixture--/new.jsonl", "new", "mock-private")
        os.utime(work, ns=(10_000_000_000, 10_000_000_000))
        self.session("agent-auto", "new-alias.jsonl", "new", "mock-private")
        auto = self.session("agent-auto", "auto.jsonl", "auto", "mock-private")
        self.session("agent-work", "x.jsonl", "legacy-conflict", "a")
        self.session("agent-auto", "y.jsonl", "legacy-conflict", "b")
        self.session("agent-work", "same-path.jsonl", "one", "a")
        self.session("agent-auto", "same-path.jsonl", "two", "b")

        before = self.snapshot()
        report = self.run_migration()
        self.assertEqual(before, self.snapshot())
        self.assertEqual(list(self.home.iterdir()), [self.pi])
        for expected in (
            "theme; canonical kept", "terminal.showImages; canonical kept",
            "quietStartup; Work and Auto disagree", "1 already canonical", "1 canonical ID conflict",
            "1 duplicate legacy copies", "2 Work/Auto ID conflict", "3 session path conflict", "2 to copy",
        ):
            self.assertIn(expected, report)
        for private in ("mock-private", "fixture", "new.jsonl", "httpProxy", "codex-old"):
            self.assertNotIn(private, report)

        report = self.run_migration(stage=True)
        (stage,) = self.home.glob("pi-cutover-*")
        self.assertIn(stage.name, report)
        self.assertEqual(stage.stat().st_mode & 0o777, 0o700)
        self.assertEqual(before, self.snapshot())
        self.assertEqual(json.loads((stage / "settings-additions.json").read_bytes()), {
            "defaultThinkingLevel": "high", "editorPaddingX": 2,
            "terminal": {"imageWidthCells": 42, "hyperlinks": False},
        })
        expected = {"--fixture--/new.jsonl": work, "auto.jsonl": auto}
        self.assertEqual({str(p.relative_to(stage / "sessions")) for p in stage.rglob("*.jsonl")}, set(expected))
        for name, source in expected.items():
            copy = stage / "sessions" / name
            self.assertEqual(copy.read_bytes(), source.read_bytes())
            self.assertEqual(copy.stat().st_mtime_ns, source.stat().st_mtime_ns)
            self.assertEqual(copy.stat().st_mode & 0o777, 0o600)

    def test_shared_links_and_unsafe_legacy_entries_never_followed(self):
        canonical = self.settings("agent", {"editorPaddingX": 2})
        self.session("agent", "shared.jsonl", "one", "shared")
        (self.pi / "agent-work" / "sessions").symlink_to(self.pi / "agent" / "sessions", target_is_directory=True)
        (self.pi / "agent-work" / "settings.json").symlink_to(canonical)
        src = self.session("agent-auto", "actual.jsonl", "two", "mock-private")
        os.link(src, self.home / "hardlink-outside-profile")  # Never copy multiply linked input.
        (src.parent / "link.jsonl").symlink_to(src)
        os.mkfifo(src.parent / "fifo.jsonl", 0o600)
        (src.parent / "invalid.jsonl").write_text("mock-private", encoding="utf-8")
        result = self.run_migration(stage=True)
        self.assertIn("agent-work: settings skipped", result)
        self.assertIn("agent-work: 1 unsafe/invalid", result)
        self.assertIn("agent-auto: 4 unsafe/invalid", result)
        self.assertIn("0 to copy", result)
        self.assertIn("Nothing to stage", result)
        self.assertNotIn("mock-private", result)
        self.assertFalse(list(self.home.glob("pi-cutover-*")))

    def test_opaque_canonical_inputs_block_only_affected_merge(self):
        source = self.settings("agent-work", {"hideThinkingBlock": True})
        self.session("agent-work", "work.jsonl", "two", "work")
        (self.pi / "agent" / "settings.json").symlink_to(source)
        self.assertIn("Settings: no additions planned", self.run_migration())
        self.assertIn("Sessions: 1 to copy", self.run_migration())
        (self.pi / "agent" / "sessions").symlink_to(self.pi / "agent-work" / "sessions", target_is_directory=True)
        report = self.run_migration(stage=True)
        self.assertIn("Sessions: no copies planned", report)
        self.assertIn("Nothing to stage", report)
        self.assertFalse(list(self.home.glob("pi-cutover-*")))

    def test_cli_refuses_agent_environment(self):
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), "--home", str(self.home), "--stage"],
            env={**os.environ, "PI_WRAPPER_PROFILE": "personal"}, capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 1)
        self.assertIn("host terminal", proc.stderr)
        self.assertEqual(list(self.home.iterdir()), [self.pi])


if __name__ == "__main__":
    unittest.main()
