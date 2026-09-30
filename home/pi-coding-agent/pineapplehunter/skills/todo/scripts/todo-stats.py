#!/usr/bin/env python3
"""Validate and list Markdown task files in priority order."""

import argparse
from datetime import datetime
from pathlib import Path


REQUIRED_FIELDS = ("title", "created", "status", "priority")
NONEMPTY_FIELDS = REQUIRED_FIELDS
PRIORITIES = {f"P{number}": number for number in range(4)}
STATUSES = {"pending", "in-progress", "blocked", "deferred", "completed"}


TIMESTAMP_FORMAT = "%Y-%m-%d %H:%M:%S"


def validate_timestamp(path: Path, field: str, value: str) -> None:
    try:
        parsed = datetime.strptime(value, TIMESTAMP_FORMAT)
    except ValueError:
        raise ValueError(f"{path}: invalid {field} timestamp: {value}") from None
    if parsed.strftime(TIMESTAMP_FORMAT) != value:
        raise ValueError(f"{path}: invalid {field} timestamp: {value}")


def read_frontmatter(path: Path) -> dict[str, str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError(f"{path}: missing front matter")

    fields: dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if ":" not in line:
            raise ValueError(f"{path}: invalid front matter line: {line}")
        key, value = line.split(":", 1)
        key = key.strip()
        if not key:
            raise ValueError(f"{path}: empty front matter key")
        if key in fields:
            raise ValueError(f"{path}: duplicate front matter field: {key}")
        fields[key] = value.strip()
    else:
        raise ValueError(f"{path}: unterminated front matter")

    missing = [field for field in REQUIRED_FIELDS if field not in fields]
    if missing:
        raise ValueError(f"{path}: missing front matter field(s): {', '.join(missing)}")
    empty = [field for field in NONEMPTY_FIELDS if not fields[field]]
    if empty:
        raise ValueError(f"{path}: empty front matter field(s): {', '.join(empty)}")
    for optional in ("base", "tag"):
        if optional in fields and not fields[optional]:
            raise ValueError(f"{path}: empty front matter field: {optional}")
    if fields["priority"] not in PRIORITIES:
        raise ValueError(f"{path}: invalid priority: {fields['priority']}")
    if fields["status"] not in STATUSES:
        raise ValueError(f"{path}: invalid status: {fields['status']}")

    validate_timestamp(path, "created", fields["created"])
    finished = fields.get("finished", "")
    if finished:
        validate_timestamp(path, "finished", finished)
    if fields["status"] == "completed" and not finished:
        raise ValueError(f"{path}: completed task has no finished timestamp")
    if fields["status"] != "completed" and finished:
        raise ValueError(f"{path}: unfinished task has a finished timestamp")
    return fields


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()

    tasks: list[tuple[Path, dict[str, str]]] = []
    try:
        if args.directory.exists() and not args.directory.is_dir():
            raise ValueError(f"{args.directory}: not a directory")
        if args.directory.is_dir():
            for path in args.directory.glob("*.md"):
                if path.name != "README.md":
                    tasks.append((path, read_frontmatter(path)))
    except (OSError, UnicodeError, ValueError) as error:
        parser.error(str(error))

    unfinished = [task for task in tasks if task[1]["status"] != "completed"]
    unfinished.sort(
        key=lambda task: (
            PRIORITIES[task[1]["priority"]],
            task[1]["created"],
            task[0].name,
        )
    )
    print(f"Tasks ({len(unfinished)})")
    for path, task in unfinished:
        details = [f"created {task['created']}"]
        if task.get("base"):
            details.append(f"base {task['base']}")
        if task.get("tag"):
            details.append(f"tag {task['tag']}")
        print(
            f"  [{task['priority']}] {task['title']} -- {task['status']} "
            f"({'; '.join(details)}; {path.name})"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
