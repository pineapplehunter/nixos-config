import json
import runpy
import tempfile
import unittest
from pathlib import Path

update = runpy.run_path(str(Path(__file__).resolve().parents[1] / "update-mcp.py"))["update"]


class UpdateMcpTests(unittest.TestCase):
    def test_merge_and_removal(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mcp.json"
            unrelated = {"command": "other-server"}
            path.write_text(json.dumps({"extra": True, "mcpServers": {"other": unrelated}}))
            path.chmod(0o600)
            update(path, {"host": {"command": "bridge"}})
            settings = json.loads(path.read_text())
            assert settings["extra"] and settings["mcpServers"]["other"] == unrelated
            assert settings["mcpServers"]["host"]["command"] == "bridge"
            assert path.stat().st_mode & 0o777 == 0o600
            update(path, {})
            assert json.loads(path.read_text())["mcpServers"] == {"other": unrelated}

    def test_user_modified_obsolete_entry_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "new" / "mcp.json"
            update(path, {"host": {"command": "bridge"}})
            assert path.stat().st_mode & 0o777 == 0o600
            path.write_text(json.dumps({"mcpServers": {"host": {"command": "custom"}}}))
            update(path, {})
            assert json.loads(path.read_text())["mcpServers"]["host"]["command"] == "custom"


if __name__ == "__main__":
    unittest.main()
