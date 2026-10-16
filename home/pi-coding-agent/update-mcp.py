"""Merge host MCP registrations without replacing unrelated user servers."""

import json
import sys
from pathlib import Path


def update(path: Path, servers: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    managed_path = path.with_name(".host-mcp-servers.json")
    settings = json.loads(path.read_text()) if path.exists() else {}
    previous = json.loads(managed_path.read_text()) if managed_path.exists() else {}
    entries = settings.setdefault("mcpServers", {})
    for name, entry in previous.items():
        if name not in servers and entries.get(name) == entry:
            del entries[name]
    entries.update(servers)
    temporary = path.with_suffix(".json.tmp")
    temporary.touch(mode=0o600)
    temporary.chmod(path.stat().st_mode & 0o777 if path.exists() else 0o600)
    temporary.write_text(json.dumps(settings, indent=2) + "\n")
    temporary.replace(path)
    managed_path.write_text(json.dumps(servers, indent=2) + "\n")


if __name__ == "__main__":
    update(Path(sys.argv[1]), json.loads(sys.argv[2]))
