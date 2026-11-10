"""One-way wl-copy compatibility client for Pi's clipboard broker."""

import asyncio
import sys

from dbus_next import DBusError, Message, MessageType
from dbus_next.aio import MessageBus

BUS_NAME = "io.github.pineapplehunter.LocalClipboard1"
INTERFACE = BUS_NAME
OBJECT_PATH = "/io/github/pineapplehunter/LocalClipboard1"
MAX_CLIPBOARD_BYTES = 8 * 1024 * 1024


async def copy(data):
    connection = MessageBus()
    try:
        await connection.connect()
        reply = await connection.call(
            Message(
                destination=BUS_NAME,
                path=OBJECT_PATH,
                interface=INTERFACE,
                member="Copy",
                signature="ay",
                body=[data],
            )
        )
        if reply.message_type == MessageType.ERROR:
            raise DBusError._from_message(reply)
    finally:
        connected = connection.connected
        connection.disconnect()
        if connected:
            await connection.wait_for_disconnect()


def main() -> int:
    if len(sys.argv) != 1:
        print(
            "wl-copy: options are not supported by the Pi clipboard broker",
            file=sys.stderr,
        )
        return 2

    data = sys.stdin.buffer.read(MAX_CLIPBOARD_BYTES + 1)
    if len(data) > MAX_CLIPBOARD_BYTES:
        print("wl-copy: clipboard content exceeds 8 MiB", file=sys.stderr)
        return 1

    try:
        data.decode("utf-8")

        async def run():
            await asyncio.wait_for(copy(data), 5)

        asyncio.run(run())
        return 0
    except (
        DBusError,
        OSError,
        RuntimeError,
        UnicodeDecodeError,
        TimeoutError,
    ) as error:
        print(f"wl-copy: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
