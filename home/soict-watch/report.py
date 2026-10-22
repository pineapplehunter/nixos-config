"""Shared report schema validation and Slack payload construction."""

import json
from pathlib import Path
import sys

from jsonschema import Draft202012Validator


SCHEMA = json.loads(Path(__file__).with_name("report-schema.json").read_text(encoding="utf-8"))
VALIDATOR = Draft202012Validator(SCHEMA)
SUMMARY = "ホームページに変更がありました。"


def load_report(path):
    report = json.loads(Path(path).read_text(encoding="utf-8"))
    errors = list(VALIDATOR.iter_errors(report))
    if errors:
        raise ValueError("\n".join(
            f"{error.json_path}: {error.message}" for error in errors[:10]
        ))
    validate_slack_payload(slack_payload(report))
    return report


def validate_slack_payload(payload):
    """Check Slack's documented limits for the block types we generate."""
    # https://docs.slack.dev/reference/methods/chat.postMessage/
    # 4,000 is a recommendation; over 40,000 risks truncation, not rejection.
    if len(payload["text"]) > 40000:
        raise ValueError("Slack fallback text exceeds the 40000-character truncation threshold")
    # https://docs.slack.dev/reference/block-kit/blocks/
    if len(payload["blocks"]) > 50:
        raise ValueError("Slack message exceeds 50 top-level blocks")

    def check_block(block, path):
        if block["type"] == "container":
            # https://docs.slack.dev/reference/block-kit/blocks/container-block/
            if len(block["title"]["text"]) > 150:
                raise ValueError(f"{path}.title exceeds Slack's 150-character limit")
            children = block["child_blocks"]
            if len(children) > 10:
                raise ValueError(f"{path}.child_blocks exceeds Slack's 10-block limit")
            for index, child in enumerate(children):
                check_block(child, f"{path}.child_blocks[{index}]")
        elif block["type"] == "section":
            # https://docs.slack.dev/reference/block-kit/blocks/section-block/
            if len(block["text"]["text"]) > 3000:
                raise ValueError(f"{path}.text exceeds Slack's 3000-character limit")

    for index, block in enumerate(payload["blocks"]):
        check_block(block, f"blocks[{index}]")


def slack_payload(report):
    return {
        "text": SUMMARY,
        "blocks": [
            {"type": "section", "text": {"type": "plain_text", "text": SUMMARY}},
            *[
                {
                    "type": "container",
                    "title": {"type": "plain_text", "text": category["title"]},
                    "is_collapsible": True,
                    "default_collapsed": True,
                    "child_blocks": [
                        {"type": "section", "text": {"type": "plain_text", "text": section}}
                        for section in category["sections"]
                    ],
                }
                for category in report["categories"]
            ],
        ],
        "unfurl_links": False,
        "unfurl_media": False,
    }


if __name__ == "__main__":
    try:
        load_report(sys.argv[1])
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    print("Report JSON and schema are valid")
