"""Run only under a private dbus-run-session, never the desktop session bus."""

import asyncio
import json
import os
import sys
import tempfile
from dataclasses import replace
from pathlib import Path
from uuid import uuid4

from dbus_next import Message, MessageType
from dbus_next.aio import MessageBus
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from radicale_agent.config import Config
from radicale_agent.daemon import CalendarInterface
from radicale_agent.service import CalendarService
from radicale_agent.transport import BUS_NAME, OBJECT_PATH, read
from support import WritableBackend, config


async def main():
    live = os.environ.get("RADICALE_TRANSPORT_LIVE") == "1"
    if live:
        assert os.environ.get("RADICALE_LIVE_WRITE_TEST") == "1"
        service = CalendarService(Config.from_env())
        assert service.config.writes_enabled
    else:
        service = CalendarService(
            replace(config(), writes_enabled=True), WritableBackend()
        )
    bus = await MessageBus().connect()
    bus.export(OBJECT_PATH, CalendarInterface(service))
    await bus.request_name(BUS_NAME)
    with tempfile.TemporaryDirectory(prefix="radicale-proxy-") as directory:
        socket = Path(directory) / "bus"
        proxy = await asyncio.create_subprocess_exec(
            "xdg-dbus-proxy",
            os.environ["DBUS_SESSION_BUS_ADDRESS"],
            str(socket),
            "--filter",
            f"--call={BUS_NAME}={BUS_NAME}.Read@{OBJECT_PATH}",
            f"--call={BUS_NAME}={BUS_NAME}.Write@{OBJECT_PATH}",
        )
        try:
            async with asyncio.timeout(5):
                while not socket.exists():
                    assert proxy.returncode is None
                    await asyncio.sleep(0.01)
            os.environ["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={socket}"
            await verify_tools(live)
        finally:
            proxy.terminate()
            await proxy.wait()
            bus.disconnect()


async def verify_tools(live):
    probe = await MessageBus().connect()
    try:
        denied = await probe.call(
            Message(
                destination=BUS_NAME,
                path=OBJECT_PATH,
                interface="org.freedesktop.DBus.Introspectable",
                member="Introspect",
            )
        )
        assert denied.message_type == MessageType.ERROR
        assert (await read("list_collections", {}))["data"]["items"][0]["id"] == "Agent"
        assert (await read("complete_task", {}))["error"]["code"] == "READ_ONLY"
        assert not (await read("get_event", {"collection_id": "private", "uid": "x"}))[
            "ok"
        ]
        # No credentials or even their file path reach the MCP subprocess.
        env = {
            k: v
            for k, v in os.environ.items()
            if not k.startswith(("CALDAV_", "APP_TIMEZONE"))
        }
        params = StdioServerParameters(
            command=sys.executable, args=["-m", "radicale_agent.server"], env=env
        )
        async with stdio_client(params) as (reader, writer):  # noqa: SIM117 - SDK lifetimes
            async with ClientSession(reader, writer) as session:
                await session.initialize()
                tools = (await session.list_tools()).tools
                assert {t.name for t in tools} == {
                    "list_collections",
                    "list_events",
                    "get_event",
                    "list_tasks",
                    "get_task",
                    "create_event",
                    "update_event",
                    "create_task",
                    "update_task",
                    "complete_task",
                    "delete_event",
                    "delete_task",
                }
                for tool in tools:
                    if tool.name.startswith("delete_"):
                        assert (
                            tool.annotations.destructiveHint
                            and tool.annotations.idempotentHint
                        )
                    if tool.name != "list_collections":
                        assert (
                            tool.inputSchema["properties"]["collection_id"]["const"]
                            == "Agent"
                        )

                async def call(name, **arguments):
                    result = await session.call_tool(
                        name,
                        {"collection_id": "Agent", **arguments}
                        if name != "list_collections"
                        else {},
                    )
                    assert not result.isError, result
                    assert result.structuredContent["ok"], result.structuredContent.get(
                        "error"
                    )
                    return result.structuredContent["data"]["items"]

                assert (await call("list_collections"))[0]["id"] == "Agent"
                event_id, task_id = str(uuid4()), str(uuid4())
                if live and os.environ.get("RADICALE_LIVE_FIXTURE_LOG"):
                    with Path(os.environ["RADICALE_LIVE_FIXTURE_LOG"]).open(  # noqa: ASYNC230 - test-only UID log
                        "a"
                    ) as file:
                        file.writelines(
                            json.dumps({"uid": "agent-" + identifier, "kind": kind})
                            + "\n"
                            for identifier, kind in [
                                (event_id, "mcp-event"),
                                (task_id, "mcp-task"),
                            ]
                        )
                event_args = {
                    "request_id": event_id,
                    "title": "[Agent integration test] MCP event",
                    "start": "2026-10-20T14:00:00+09:00",
                    "end": "2026-10-20T15:00:00+09:00",
                }
                event = (await call("create_event", **event_args))[0]
                assert (await call("create_event", **event_args))[0]["uid"] == event[
                    "uid"
                ]
                assert (await call("get_event", uid=event["uid"]))[0]["etag"] == event[
                    "etag"
                ]
                assert any(
                    item["uid"] == event["uid"]
                    for item in await call(
                        "list_events", start="2026-10-20", end="2026-10-21"
                    )
                )
                changed = (
                    await call(
                        "update_event",
                        uid=event["uid"],
                        expected_etag=event["etag"],
                        changes={
                            "title": event["title"] + " updated",
                            "location": "Test desk",
                        },
                    )
                )[0]
                assert changed["location"] == "Test desk"
                task = (
                    await call(
                        "create_task",
                        request_id=task_id,
                        title="[Agent integration test] MCP task",
                        due="2026-10-22",
                        priority=5,
                    )
                )[0]
                assert (await call("get_task", uid=task["uid"]))[0]["priority"] == 5
                assert any(
                    item["uid"] == task["uid"] for item in await call("list_tasks")
                )
                updated = (
                    await call(
                        "update_task",
                        uid=task["uid"],
                        expected_etag=task["etag"],
                        changes={
                            "priority": 2,
                            "due": "2026-10-23T12:00:00+09:00",
                            "percent_complete": 50,
                        },
                    )
                )[0]
                assert updated["status"] == "IN-PROCESS" and updated["priority"] == 2
                done = (
                    await call(
                        "complete_task", uid=task["uid"], expected_etag=updated["etag"]
                    )
                )[0]
                assert done["status"] == "COMPLETED" and done["percent_complete"] == 100
                repeated = (
                    await call(
                        "complete_task", uid=task["uid"], expected_etag=updated["etag"]
                    )
                )[0]
                assert (
                    repeated["completed_at"] == done["completed_at"]
                    and repeated["etag"] == done["etag"]
                )
                stale = await session.call_tool(
                    "delete_event",
                    {
                        "collection_id": "Agent",
                        "uid": event["uid"],
                        "expected_etag": event["etag"],
                    },
                )
                assert stale.structuredContent["error"]["code"] == "CONFLICT"
                for kind, value in [("event", changed), ("task", done)]:
                    deleted = (
                        await call(
                            "delete_" + kind,
                            uid=value["uid"],
                            expected_etag=value["etag"],
                        )
                    )[0]
                    assert deleted["deleted"] and not deleted["already_absent"]
                    assert (
                        await call(
                            "delete_" + kind,
                            uid=value["uid"],
                            expected_etag=value["etag"],
                        )
                    )[0]["already_absent"]
                    missing = await session.call_tool(
                        "get_" + kind, {"collection_id": "Agent", "uid": value["uid"]}
                    )
                    assert missing.structuredContent["error"]["code"] == "NOT_FOUND"
                invalid = await session.call_tool(
                    "get_event", {"collection_id": "Personal", "uid": "x"}
                )
                assert invalid.isError
    finally:
        probe.disconnect()


asyncio.run(main())
