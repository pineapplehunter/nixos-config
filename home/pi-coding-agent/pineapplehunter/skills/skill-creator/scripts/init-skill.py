#!/usr/bin/env python3
"""Create a minimal Agent Skill directory without overwriting existing files."""

import argparse
import re
from pathlib import Path


VALID_NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
RESOURCE_NAMES = {"scripts", "references", "assets"}


def parse_resources(value: str) -> list[str]:
    resources = [item.strip() for item in value.split(",") if item.strip()]
    invalid = sorted(set(resources) - RESOURCE_NAMES)
    if invalid:
        raise argparse.ArgumentTypeError(
            f"unknown resources: {', '.join(invalid)}; expected scripts,references,assets"
        )
    return list(dict.fromkeys(resources))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name")
    parser.add_argument("--path", required=True, type=Path, help="parent directory")
    parser.add_argument("--resources", default=[], type=parse_resources)
    args = parser.parse_args()

    if len(args.name) > 64 or not VALID_NAME.fullmatch(args.name):
        parser.error(
            "name must be at most 64 characters and contain lowercase letters, "
            "digits, and single hyphens only"
        )

    skill_dir = args.path.expanduser().resolve() / args.name
    if skill_dir.exists():
        parser.error(f"refusing to overwrite existing path: {skill_dir}")

    skill_dir.mkdir(parents=True)
    title = args.name.replace("-", " ").title()
    (skill_dir / "SKILL.md").write_text(
        f"""---
name: {args.name}
description: TODO — explain what this skill does and when it should be used.
---

# {title}

## Instructions

TODO: Add concise, actionable instructions.
""",
        encoding="utf-8",
    )
    for resource in args.resources:
        (skill_dir / resource).mkdir()

    print(skill_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
