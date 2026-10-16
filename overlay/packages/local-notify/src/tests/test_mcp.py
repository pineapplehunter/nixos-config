import asyncio
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from notification import send_discord


class NotificationTests(unittest.TestCase):
    def test_stdio(self):
        asyncio.run(self.roundtrip())

    async def roundtrip(self):
        params = StdioServerParameters(
            command=sys.executable,
            args=[str(Path(__file__).with_name("stdio_backend.py"))],
        )
        async with stdio_client(params) as (reader, writer):  # noqa: SIM117 - SDK lifetimes
            async with ClientSession(reader, writer) as session:
                await session.initialize()
                tools = (await session.list_tools()).tools
                assert [t.name for t in tools] == ["notify"]
                assert not tools[0].annotations.idempotentHint
                assert set(tools[0].inputSchema["properties"]) == {
                    "title",
                    "content",
                    "color",
                }
                result = await session.call_tool(
                    "notify",
                    {"title": "Done", "content": "**Success**", "color": "#57F287"},
                )
                assert (
                    not result.isError
                    and result.content[0].text == "Notification sent."
                )
                for arguments in [
                    {"title": "", "content": "body"},
                    {"title": "Done", "content": "body", "color": "bad"},
                    {"title": "Done", "content": "x" * 4097},
                    {"title": "fail", "content": "body"},
                ]:
                    result = await session.call_tool("notify", arguments)
                    assert result.isError
                    assert "SECRET_WEBHOOK" not in str(result)
                    assert "private exception" not in str(result)

    def test_existing_delivery_payload(self):
        import json

        with patch("notification.urllib.request.urlopen") as request:
            request.return_value.__enter__.return_value.status = 204
            send_discord(
                "https://example.test/secret",
                "pueue",
                "https://example.test/icon.png",
                "Done",
                "body",
                "",
            )
        payload = json.loads(request.call_args.args[0].data)
        assert payload["username"] == "pueue"
        assert payload["allowed_mentions"] == {"parse": []}
        assert payload["embeds"][0]["description"] == "body"


if __name__ == "__main__":
    unittest.main()
