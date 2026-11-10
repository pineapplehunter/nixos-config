import argparse
import asyncio
import os
import pathlib
import sys

from dbus_next import DBusError, Message, MessageType
from dbus_next.aio import MessageBus

from notification import (
    BUS_NAME, INTERFACE, OBJECT_PATH, ValidationError, validate,
)


async def notify(args) -> None:
    bus = MessageBus()
    try:
        await bus.connect()
        reply = await asyncio.wait_for(
            bus.call(Message(
                destination=BUS_NAME,
                path=OBJECT_PATH,
                interface=INTERFACE,
                member="Notify",
                signature="sssss",
                body=[args.username, args.icon, args.title,
                      args.content, args.color],
            )),
            timeout=20,
        )
        if reply.message_type == MessageType.ERROR:
            raise DBusError(reply.error_name, reply.body[0])
    finally:
        connected = bus.connected
        bus.disconnect()
        try:
            if connected:
                await bus.wait_for_disconnect()
        finally:
            bus._stream.close()
            bus._sock.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--username", required=True)
    parser.add_argument(
        "--icon", required=True, help="HTTPS URL for the Discord avatar"
    )
    parser.add_argument("--title", required=True)
    parser.add_argument("--content", required=True)
    parser.add_argument(
        "--color", default="", help="Discord embed color in #RRGGBB form"
    )
    args = parser.parse_args()

    try:
        validate(
            args.username, args.icon, args.title, args.content, args.color
        )
        if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
            runtime_directory = os.environ.get("XDG_RUNTIME_DIR")
            if not runtime_directory:
                raise RuntimeError(
                    "neither DBUS_SESSION_BUS_ADDRESS nor "
                    "XDG_RUNTIME_DIR is set"
                )
            os.environ["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=" + str(
                pathlib.Path(runtime_directory) / "bus"
            )

        asyncio.run(notify(args))
        return 0
    except (ValidationError, DBusError, OSError, RuntimeError,
            EOFError, asyncio.TimeoutError) as error:
        detail = f"{error.type}: {error}" if isinstance(error, DBusError) else str(error)
        print(f"local-notify: {detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
