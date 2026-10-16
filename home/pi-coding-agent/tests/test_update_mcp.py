import json
import runpy
import tempfile
import unittest
from pathlib import Path

update = runpy.run_path(str(Path(__file__).resolve().parents[1] / "update-mcp.py"))[
    "update"
]


class UpdateMcpTests(unittest.TestCase):
    def test_merge_and_removal(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mcp.json"
            unrelated = {"command": "other-server"}
            path.write_text(
                json.dumps({"extra": True, "mcpServers": {"other": unrelated}})
            )
            path.chmod(0o600)
            update(path, {"host": {"command": "bridge"}})
            settings = json.loads(path.read_text())
            assert settings["extra"] and settings["mcpServers"]["other"] == unrelated
            assert settings["mcpServers"]["host"]["command"] == "bridge"
            assert path.stat().st_mode & 0o777 == 0o600
            update(path, {})
            assert json.loads(path.read_text())["mcpServers"] == {"other": unrelated}

    def test_symlink_inputs_cannot_copy_host_secrets(self):
        for name in ["mcp.json", ".host-mcp-servers.json"]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                secret = root / "secret.json"
                secret.write_text('{"password":"host-only"}')
                profile = root / "profile"
                profile.mkdir()
                (profile / name).symlink_to(secret)
                with self.assertRaises(OSError):
                    update(profile / "mcp.json", {})
                assert secret.read_text() == '{"password":"host-only"}'
                if name != "mcp.json":
                    assert not (profile / "mcp.json").exists()

    def test_symlink_directory_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "host").mkdir()
            (root / "profile").symlink_to(root / "host", target_is_directory=True)
            with self.assertRaises(OSError):
                update(root / "profile" / "mcp.json", {})
            assert not (root / "host" / "mcp.json").exists()

    def test_old_predictable_temporary_symlink_is_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            secret = root / "secret.json"
            secret.write_text('{"password":"host-only"}')
            (root / "mcp.json.tmp").symlink_to(secret)
            update(root / "mcp.json", {"host": {"command": "bridge"}})
            assert secret.read_text() == '{"password":"host-only"}'
            assert "password" not in (root / "mcp.json").read_text()

    def test_user_modified_obsolete_entry_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "new" / "mcp.json"
            update(path, {"host": {"command": "bridge"}})
            assert path.stat().st_mode & 0o777 == 0o600
            path.write_text(json.dumps({"mcpServers": {"host": {"command": "custom"}}}))
            update(path, {})
            assert (
                json.loads(path.read_text())["mcpServers"]["host"]["command"]
                == "custom"
            )


if __name__ == "__main__":
    unittest.main()
