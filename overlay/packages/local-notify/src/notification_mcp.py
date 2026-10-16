"""Normal host-side MCP stdio server for Discord notifications."""

import argparse
import asyncio
import pathlib
import sys
from typing import Annotated

from mcp.server.fastmcp import FastMCP
from mcp.server.fastmcp.exceptions import ToolError
from mcp.types import ToolAnnotations
from notification import ValidationError, send_discord
from pydantic import Field

DEFAULT_ICON = "https://raw.githubusercontent.com/pineapplehunter/nixos-config/main/home/notification-icons/pi.png"


def create_server(webhook_url: str, username: str = "pi", icon: str = DEFAULT_ICON):
    server = FastMCP(
        "Host notifications",
        instructions="Send notifications as Discord embed Markdown. Use #57F287 for successful results, #ED4245 for failures, and omit color for neutral messages. Delivery is not idempotent: do not automatically retry after an uncertain result.",
    )

    @server.tool(
        annotations=ToolAnnotations(
            readOnlyHint=False,
            destructiveHint=False,
            idempotentHint=False,
            openWorldHint=True,
        )
    )
    async def notify(
        title: str,
        content: str,
        color: Annotated[str, Field(pattern=r"^#[0-9A-Fa-f]{6}$")] | None = None,
    ) -> str:
        """Send the user a Discord notification. Content supports Discord Markdown; prefer it for structured messages. Use #57F287 for success, #ED4245 for failure, or omit color for neutral messages."""
        try:
            await asyncio.to_thread(
                send_discord, webhook_url, username, icon, title, content, color or ""
            )
        except ValidationError as error:
            raise ToolError(str(error)) from None
        except Exception:  # noqa: BLE001 - never return webhook URLs or transport exception text
            raise ToolError(
                "Notification delivery failed; check the host notification service. Delivery may be uncertain; do not blindly retry."
            ) from None
        return "Notification sent."

    return server


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--webhook-file", required=True)
    parser.add_argument("--username", default="pi")
    parser.add_argument("--icon", default=DEFAULT_ICON)
    args = parser.parse_args()
    try:
        webhook = pathlib.Path(args.webhook_file).read_text().strip()
        if not webhook:
            raise ValueError("Empty webhook")
        create_server(webhook, args.username, args.icon).run(transport="stdio")
        return 0
    except Exception:  # noqa: BLE001 - do not log credentials
        print(
            "local-notify-mcp: check the host webhook file and service configuration",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
