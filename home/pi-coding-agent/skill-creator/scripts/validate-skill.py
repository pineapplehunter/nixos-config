#!/usr/bin/env python3
"""Perform dependency-free structural validation of an Agent Skill."""

import argparse
import re
from pathlib import Path


VALID_NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
FIELD = re.compile(r"^([A-Za-z0-9_-]+):(?:[ \t]*(.*))?$")


def frontmatter(path: Path) -> tuple[dict[str, str], str]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        raise ValueError("SKILL.md must begin with YAML frontmatter")
    try:
        end = lines.index("---", 1)
    except ValueError:
        raise ValueError("SKILL.md has unterminated YAML frontmatter") from None

    fields: dict[str, str] = {}
    current = ""
    for line in lines[1:end]:
        match = FIELD.match(line)
        if match:
            current, value = match.groups()
            if current in fields:
                raise ValueError(f"duplicate frontmatter field: {current}")
            fields[current] = (value or "").strip()
        elif current and (line.startswith(" ") or line.startswith("\t")):
            fields[current] = f"{fields[current]} {line.strip()}".strip()
        elif line.strip():
            raise ValueError(f"unsupported frontmatter syntax: {line}")
    return fields, "\n".join(lines[end + 1 :]).strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()

    directory = args.directory.expanduser().resolve()
    path = directory / "SKILL.md"
    try:
        if not path.is_file():
            raise ValueError(f"missing file: {path}")
        fields, body = frontmatter(path)
        name = fields.get("name", "").strip("'\"")
        description = fields.get("description", "").strip("'\"")
        if not name:
            raise ValueError("missing or empty name")
        if len(name) > 64 or not VALID_NAME.fullmatch(name):
            raise ValueError("name must be lowercase hyphenated text of at most 64 characters")
        if directory.name != name:
            raise ValueError(f"directory name {directory.name!r} does not match skill name {name!r}")
        if not description or description in {">", "|", ">-", "|-"}:
            raise ValueError("missing or empty description")
        if "TODO" in description:
            raise ValueError("description still contains a TODO placeholder")
        if len(description) > 1024:
            raise ValueError("description exceeds 1024 characters")
        if not body:
            raise ValueError("skill instruction body is empty")
    except (OSError, UnicodeError, ValueError) as error:
        parser.error(str(error))

    print(f"valid skill: {directory}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
