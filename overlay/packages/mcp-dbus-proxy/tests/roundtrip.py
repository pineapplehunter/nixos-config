"""Exercise actual MCP stdio across the same method filter used by the sandbox."""

import asyncio
import os
import sys
import tempfile
from contextlib import AsyncExitStack, suppress
from pathlib import Path

from dbus_next import Message, MessageType
from dbus_next.aio import MessageBus
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp_dbus_proxy import INTERFACE, OBJECT_PATH
from mcp_dbus_proxy.host import Host

NAME = "io.github.pineapplehunter.McpTest1"


async def main():
    host = Host([sys.executable, str(Path(__file__).with_name("backend.py"))])
    serving = asyncio.create_task(host.run(NAME))
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
                    body=[NAME],
                )
            )
            if reply.body[0]:
                break
            await asyncio.sleep(0.01)
        probe.disconnect()
    with tempfile.TemporaryDirectory() as directory:
        socket = Path(directory) / "bus"
        proxy = await asyncio.create_subprocess_exec(
            "xdg-dbus-proxy",
            os.environ["DBUS_SESSION_BUS_ADDRESS"],
            str(socket),
            "--filter",
            *(
                f"--call={NAME}={INTERFACE}.{method}@{OBJECT_PATH}"
                for method in ["Open", "Send", "Receive", "Close"]
            ),
        )
        try:
            async with asyncio.timeout(5):
                while not socket.exists():
                    await asyncio.sleep(0.01)
            os.environ["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={socket}"
            async with AsyncExitStack() as stack:
                first = await MessageBus().connect()
                second = await MessageBus().connect()

                async def call(
                    bus, member, signature="", body=None, interface=INTERFACE
                ):
                    return await bus.call(
                        Message(
                            destination=NAME,
                            path=OBJECT_PATH,
                            interface=interface,
                            member=member,
                            signature=signature,
                            body=body or [],
                        )
                    )

                denied = await call(
                    first, "Introspect", interface="org.freedesktop.DBus.Introspectable"
                )
                assert denied.message_type == MessageType.ERROR
                identifier = (await call(first, "Open")).body[0]
                pid = host.sessions[identifier].process
                assert (
                    await call(second, "Close", "s", [identifier])
                ).message_type == MessageType.ERROR
                first.disconnect()
                async with asyncio.timeout(5):
                    while identifier in host.sessions or pid.returncode is None:
                        await asyncio.sleep(0.01)
                second.disconnect()
                params = StdioServerParameters(
                    command=sys.executable,
                    args=["-m", "mcp_dbus_proxy.client", "--service", NAME],
                    env=dict(os.environ),
                )
                sessions = []
                for _ in range(2):
                    reader, writer = await stack.enter_async_context(
                        stdio_client(params)
                    )
                    session = await stack.enter_async_context(
                        ClientSession(reader, writer)
                    )
                    initialized = await session.initialize()
                    assert "Instructions survive" in initialized.instructions
                    sessions.append(session)
                assert len(host.sessions) == 2
                results = await asyncio.gather(
                    *(
                        session.call_tool("echo", {"text": "hello"})
                        for session in sessions
                    )
                )
                assert all(result.content[0].text == "hello" for result in results)
                assert (await sessions[0].read_resource("fixture://hello")).contents[
                    0
                ].text == "Resource content"
                large = await sessions[0].call_tool("large")
                assert not large.is_error, large
                assert len(large.structured_content["value"]) == 2 * 1024 * 1024 - 1024
                slow = asyncio.create_task(sessions[0].call_tool("slow"))
                await asyncio.sleep(0.1)
                slow.cancel()
                with suppress(asyncio.CancelledError):
                    await slow
                assert (
                    await sessions[0].call_tool("echo", {"text": "after cancellation"})
                ).content[0].text == "after cancellation"
            async with asyncio.timeout(5):
                while host.sessions:
                    await asyncio.sleep(0.01)
        finally:
            proxy.terminate()
            await proxy.wait()
            serving.cancel()
            with suppress(asyncio.CancelledError):
                await serving


asyncio.run(main())
