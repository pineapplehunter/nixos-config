"""Versioned, narrow D-Bus protocol shared by broker and client."""

import asyncio
import json

from dbus_next import Message, MessageType
from dbus_next.aio import MessageBus
from dbus_next.errors import AuthError, DBusError

from .errors import failure

BUS_NAME = "io.github.pineapplehunter.Radicale1"
OBJECT_PATH = "/io/github/pineapplehunter/Radicale1"
INTERFACE = BUS_NAME
CALL_TIMEOUT = 90


async def read(action: str, arguments: dict) -> dict:
    return await call("Read", action, arguments)


async def write(action: str, arguments: dict) -> dict:
    return await call("Write", action, arguments)


async def call(member: str, action: str, arguments: dict) -> dict:
    bus = None
    try:
        bus = await MessageBus().connect()
        reply = await asyncio.wait_for(
            bus.call(
                Message(
                    destination=BUS_NAME,
                    path=OBJECT_PATH,
                    interface=INTERFACE,
                    member=member,
                    signature="ss",
                    body=[action, json.dumps(arguments)],
                )
            ),
            timeout=CALL_TIMEOUT,
        )
        if reply.message_type == MessageType.ERROR or reply.signature != "s":
            return failure(
                "BROKER_UNAVAILABLE",
                "The host calendar broker is unavailable or denied by the sandbox bus policy.",
            )
        return json.loads(reply.body[0])
    except (OSError, TimeoutError, ValueError, EOFError, AuthError, DBusError):
        return failure(
            "BROKER_UNAVAILABLE",
            "Check the host calendar service, session bus and sandbox proxy policy.",
        )
    finally:
        if bus is not None:
            bus.disconnect()
