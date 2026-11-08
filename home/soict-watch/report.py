"""Shared report schema validation and Slack payload construction."""

from pathlib import Path
import sys
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, TypeAdapter


class ReportModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class Category(ReportModel):
    title: Annotated[str, StringConstraints(min_length=1, max_length=100, pattern=r"\S")]
    sections: Annotated[
        list[Annotated[str, StringConstraints(min_length=1, max_length=2800, pattern=r"\S")]],
        Field(min_length=1, max_length=5),
    ]


class GroupReport(ReportModel):
    recipient: Literal["group"]
    categories: Annotated[list[Category], Field(min_length=1, max_length=6)]


class AdminReport(ReportModel):
    recipient: Literal["admin"]
    reason: Annotated[str, StringConstraints(min_length=1, max_length=1800, pattern=r"\S")]


REPORT = TypeAdapter(Annotated[GroupReport | AdminReport, Field(discriminator="recipient")])
SCHEMA = REPORT.json_schema()
SUMMARY = "ホームページに変更がありました。"


def load_report(path):
    report = REPORT.validate_json(Path(path).read_text(encoding="utf-8"))
    if report.recipient == "group":
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


def slack_payload(report: GroupReport):
    return {
        "text": SUMMARY,
        "blocks": [
            {"type": "section", "text": {"type": "plain_text", "text": SUMMARY}},
            *[
                {
                    "type": "container",
                    "title": {"type": "plain_text", "text": category.title},
                    "is_collapsible": True,
                    "default_collapsed": True,
                    "child_blocks": [
                        {"type": "section", "text": {"type": "plain_text", "text": section}}
                        for section in category.sections
                    ],
                }
                for category in report.categories
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
