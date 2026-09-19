#!/usr/bin/env python3
"""Resolve the in-tree or temporary task-list directory for a workspace."""

import argparse
import hashlib
import re
import subprocess
from pathlib import Path


def workspace_root(start: Path) -> Path:
    start = start.expanduser().resolve()
    try:
        result = subprocess.run(
            ["git", "-C", str(start), "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return start
    return Path(result.stdout.strip()).resolve()


def temporary_directory(root: Path) -> Path:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", root.name).strip("-.") or "workspace"
    digest = hashlib.sha256(str(root).encode("utf-8")).hexdigest()[:10]
    return Path("/tmp/pi-tasks") / f"{slug}-{digest}" / "todo"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("intree", "tmp"))
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--create", action="store_true")
    args = parser.parse_args()

    root = workspace_root(args.root)
    directory = root / "todo" if args.mode == "intree" else temporary_directory(root)
    if args.create:
        directory.mkdir(parents=True, exist_ok=True)
    print(directory)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
