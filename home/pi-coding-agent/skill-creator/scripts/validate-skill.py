#!/usr/bin/env python3
"""Validate the structure and YAML frontmatter of an Agent Skill."""

import argparse
import re
from pathlib import Path

import yaml


VALID_NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def read_skill(path: Path) -> tuple[dict[str, object], str]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        raise ValueError("SKILL.md must begin with YAML frontmatter")
    try:
        end = lines.index("---", 1)
    except ValueError:
        raise ValueError("SKILL.md has unterminated YAML frontmatter") from None

    try:
        fields = yaml.safe_load("\n".join(lines[1:end]))
    except yaml.YAMLError as error:
        raise ValueError(f"invalid YAML frontmatter: {error}") from None
    if not isinstance(fields, dict):
        raise ValueError("frontmatter must be a YAML mapping")
    if not all(isinstance(key, str) for key in fields):
        raise ValueError("frontmatter field names must be strings")
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
        fields, body = read_skill(path)
        name = fields.get("name")
        description = fields.get("description")
        if not isinstance(name, str) or not name:
            raise ValueError("name must be a nonempty string")
        if len(name) > 64 or not VALID_NAME.fullmatch(name):
            raise ValueError("name must be lowercase hyphenated text of at most 64 characters")
        if directory.name != name:
            raise ValueError(f"directory name {directory.name!r} does not match skill name {name!r}")
        if not isinstance(description, str) or not description.strip():
            raise ValueError("description must be a nonempty string")
        if description.lstrip().startswith("TODO"):
            raise ValueError("description still contains a TODO placeholder")
        if len(description) > 1024:
            raise ValueError("description exceeds 1024 characters")
        compatibility = fields.get("compatibility")
        if compatibility is not None and (
            not isinstance(compatibility, str) or len(compatibility) > 500
        ):
            raise ValueError("compatibility must be a string of at most 500 characters")
        metadata = fields.get("metadata")
        if metadata is not None and not isinstance(metadata, dict):
            raise ValueError("metadata must be a mapping")
        if not body:
            raise ValueError("skill instruction body is empty")
    except (OSError, UnicodeError, ValueError) as error:
        parser.error(str(error))

    print(f"valid skill: {directory}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
