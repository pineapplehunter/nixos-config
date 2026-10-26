"""Run only under a private dbus-run-session, never the desktop session bus."""

import asyncio
import json
import os
import sys
import tempfile
from contextlib import suppress
from pathlib import Path
from uuid import uuid4

from dbus_next import Message, MessageType
from dbus_next.aio import MessageBus
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp_dbus_proxy import INTERFACE, OBJECT_PATH
from mcp_dbus_proxy.host import Host

BUS_NAME = "io.github.pineapplehunter.McpRadicaleTest1"


async def main():
    live = os.environ.get("RADICALE_TRANSPORT_LIVE") == "1"
    if live:
        assert os.environ.get("RADICALE_LIVE_WRITE_TEST") == "1"
    host = Host([sys.executable, str(Path(__file__).with_name("host_backend.py"))])
    serving = asyncio.create_task(host.run(BUS_NAME))
    async with asyncio.timeout(5):
        while not hasattr(host, "bus") or not host.bus.unique_name:
            await asyncio.sleep(0.01)
        probe = await MessageBus().connect()
        while True:
            reply = await probe.call(
                Message(
                    destination="org.freedesktop.DBus",
                    path="/org/freedesktop/DBus",
                    interface="org.freedesktop.DBus",
                    member="NameHasOwner",
                    signature="s",
                    body=[BUS_NAME],
                )
            )
            if reply.body[0]:
                break
            await asyncio.sleep(0.01)
        probe.disconnect()
    with tempfile.TemporaryDirectory(prefix="radicale-proxy-") as directory:
        os.environ["XDG_RUNTIME_DIR"] = directory
        socket = Path(directory) / "bus"
        proxy = await asyncio.create_subprocess_exec(
            "xdg-dbus-proxy",
            os.environ["DBUS_SESSION_BUS_ADDRESS"],
            str(socket),
            "--filter",
            *(
                f"--call={BUS_NAME}={INTERFACE}.{method}@{OBJECT_PATH}"
                for method in ["Open", "Send", "Receive", "Close"]
            ),
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
            serving.cancel()
            with suppress(asyncio.CancelledError):
                await serving


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
        # No credentials or even their file path reach the MCP subprocess.
        env = {
            k: v
            for k, v in os.environ.items()
            if not k.startswith(("CALDAV_", "APP_TIMEZONE"))
        }
        params = StdioServerParameters(
            command=sys.executable,
            args=["-m", "mcp_dbus_proxy.client", "--service", BUS_NAME],
            env=env,
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
                            tool.annotations.read_only_hint is False
                            and tool.annotations.destructive_hint
                            and tool.annotations.idempotent_hint
                        )
                    if tool.name != "list_collections":
                        assert (
                            tool.input_schema["properties"]["collection_id"]["const"]
                            == "Agent"
                        )

                async def call(name, **arguments):
                    result = await session.call_tool(
                        name,
                        {"collection_id": "Agent", **arguments}
                        if name != "list_collections"
                        else {},
                    )
                    assert not result.is_error, result
                    assert result.structured_content["ok"], result.structured_content.get(
                        "error"
                    )
                    return result.structured_content["data"]["items"]

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
                assert stale.structured_content["error"]["code"] == "CONFLICT"
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
                    assert missing.structured_content["error"]["code"] == "NOT_FOUND"
                invalid = await session.call_tool(
                    "get_event", {"collection_id": "Personal", "uid": "x"}
                )
                assert invalid.is_error
    finally:
        probe.disconnect()


asyncio.run(main())
