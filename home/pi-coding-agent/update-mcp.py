"""Merge host MCP registrations into agent-writable, untrusted directories."""

import json
import os
import secrets
import stat
import sys
from contextlib import suppress
from pathlib import Path


def open_directory(path: Path) -> int:
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("MCP configuration requires an absolute directory")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    directory = os.open("/", flags)
    try:
        for component in path.parts[1:]:
            with suppress(FileExistsError):
                os.mkdir(component, mode=0o700, dir_fd=directory)
            child = os.open(component, flags, dir_fd=directory)
            os.close(directory)
            directory = child
        return directory
    except BaseException:
        os.close(directory)
        raise


def read_json(directory: int, name: str) -> tuple[dict, int]:
    try:
        descriptor = os.open(
            name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory
        )
    except FileNotFoundError:
        return {}, 0o600
    with os.fdopen(descriptor) as file:
        info = os.fstat(file.fileno())
        if not stat.S_ISREG(info.st_mode):
            raise ValueError("MCP configuration must be a regular file")
        return json.load(file), stat.S_IMODE(info.st_mode)


def write_json(directory: int, name: str, value: dict, mode: int) -> None:
    temporary = f".{name}.{secrets.token_hex(16)}.tmp"
    descriptor = os.open(
        temporary,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
        0o600,
        dir_fd=directory,
    )
    try:
        with os.fdopen(descriptor, "w") as file:
            os.fchmod(file.fileno(), mode)
            file.write(json.dumps(value, indent=2) + "\n")
        os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
    finally:
        with suppress(FileNotFoundError):
            os.unlink(temporary, dir_fd=directory)


def update(path: Path, servers: dict) -> None:
    # Resolve every component without symlinks and retain the directory FD.
    # An agent may replace/rename these paths while activation is running.
    directory = open_directory(path.parent)
    try:
        settings, mode = read_json(directory, path.name)
        previous, _ = read_json(directory, ".host-mcp-servers.json")
        entries = settings.setdefault("mcpServers", {})
        for name, entry in previous.items():
            if name not in servers and entries.get(name) == entry:
                del entries[name]
        entries.update(servers)
        write_json(directory, path.name, settings, mode)
        write_json(directory, ".host-mcp-servers.json", servers, 0o600)
    finally:
        os.close(directory)


if __name__ == "__main__":
    update(Path(sys.argv[1]), json.loads(sys.argv[2]))
