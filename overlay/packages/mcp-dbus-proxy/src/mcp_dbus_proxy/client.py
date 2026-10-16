"""Expose a configured host MCP endpoint as ordinary MCP stdio."""

import argparse
import asyncio
import sys
from contextlib import suppress

from dbus_next import Message, MessageType
from dbus_next.aio import MessageBus

from . import INTERFACE, MAX_MESSAGE_BYTES, OBJECT_PATH, POLL_SECONDS


async def run(service):
    bus = await MessageBus().connect()
    identifier = None
    transport = None
    output_transport = None

    async def call(member, signature="", body=None):
        reply = await asyncio.wait_for(
            bus.call(
                Message(
                    destination=service,
                    path=OBJECT_PATH,
                    interface=INTERFACE,
                    member=member,
                    signature=signature,
                    body=body or [],
                )
            ),
            POLL_SECONDS + 15,
        )
        if reply.message_type == MessageType.ERROR:
            raise RuntimeError("Host MCP session unavailable")
        return reply.body

    try:
        identifier = (await call("Open"))[0]
        reader = asyncio.StreamReader(limit=MAX_MESSAGE_BYTES + 1)
        transport, _ = await asyncio.get_running_loop().connect_read_pipe(
            lambda: asyncio.StreamReaderProtocol(reader), sys.stdin.buffer
        )

        loop = asyncio.get_running_loop()
        output_transport, protocol = await loop.connect_write_pipe(
            asyncio.streams.FlowControlMixin, sys.stdout.buffer
        )
        writer = asyncio.StreamWriter(output_transport, protocol, None, loop)

        async def send():
            while line := await reader.readline():
                if len(line) > MAX_MESSAGE_BYTES or not line.endswith(b"\n"):
                    raise ValueError("Invalid MCP stdio frame")
                await call(
                    "Send", "ss", [identifier, line.decode("utf-8").rstrip("\n")]
                )

        async def receive():
            while True:
                payload = (await call("Receive", "s", [identifier]))[0]
                if payload:
                    writer.write(payload.encode("utf-8") + b"\n")
                    await writer.drain()

        tasks = [asyncio.create_task(send()), asyncio.create_task(receive())]
        try:
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
    finally:
        if transport is not None:
            transport.close()
        if output_transport is not None:
            output_transport.close()
        if identifier is not None:
            with suppress(Exception):
                await asyncio.wait_for(call("Close", "s", [identifier]), 5)
        bus.disconnect()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--service", required=True)
    args = parser.parse_args()
    try:
        asyncio.run(run(args.service))
    except KeyboardInterrupt:
        pass
    except Exception:  # noqa: BLE001 - sanitize the process boundary
        print(
            "mcp-dbus-proxy: host MCP session unavailable; check the host service and bus policy",
            file=sys.stderr,
        )
        raise SystemExit(1)


if __name__ == "__main__":
    main()
