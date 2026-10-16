"""A mock delivery backend, never a real Discord connection."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import notification_mcp
from notification import validate


def send(webhook, username, icon, title, content, color):
    assert webhook == "SECRET_WEBHOOK"
    assert username == "pi"
    validate(username, icon, title, content, color)
    if title == "fail":
        raise RuntimeError("SECRET_WEBHOOK private exception details")


notification_mcp.send_discord = send
notification_mcp.create_server("SECRET_WEBHOOK").run(transport="stdio")
