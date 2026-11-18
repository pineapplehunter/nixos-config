"""Git's ssh-keygen-compatible client for the host commit signing broker."""

import argparse
import asyncio
import os
from pathlib import Path
import sys

from dbus_next import DBusError, Message, MessageType
from dbus_next.aio import MessageBus

BUS_NAME = "io.github.pineapplehunter.GitSign1"
OBJECT_PATH = "/io/github/pineapplehunter/GitSign1"
MAX_PAYLOAD_BYTES = 1024 * 1024


async def sign(payload):
    connection = MessageBus()
    try:
        await connection.connect()
        reply = await connection.call(
            Message(
                destination=BUS_NAME,
                path=OBJECT_PATH,
                interface=BUS_NAME,
                member="SignCommit",
                signature="ay",
                body=[payload],
            )
        )
        if reply.message_type == MessageType.ERROR:
            raise DBusError._from_message(reply)
        return bytes(reply.body[0])
    finally:
        connected = connection.connected
        connection.disconnect()
        if connected:
            await connection.wait_for_disconnect()


def main():
    # Verification stays local and never calls the host signing service.
    if (
        len(sys.argv) > 2
        and sys.argv[1] == "-Y"
        and sys.argv[2] in {"find-principals", "verify", "check-novalidate"}
    ):
        os.execvp("ssh-keygen", ["ssh-keygen", *sys.argv[1:]])
    parser = argparse.ArgumentParser()
    parser.add_argument("-Y", choices=["sign"], required=True)
    parser.add_argument("-n", choices=["git"], required=True)
    parser.add_argument(
        "-f", required=True
    )  # Public key; host selects its own.
    parser.add_argument("-U", action="store_true")
    parser.add_argument("payload", type=Path)
    args = parser.parse_args()
    try:
        with args.payload.open("rb") as stream:
            payload = stream.read(MAX_PAYLOAD_BYTES + 1)
        if len(payload) > MAX_PAYLOAD_BYTES:
            raise ValueError("commit payload exceeds 1 MiB")

        async def request():
            return await asyncio.wait_for(sign(payload), 35)

        signature = asyncio.run(request())
        Path(str(args.payload) + ".sig").write_bytes(signature)
        return 0
    except (
        DBusError,
        OSError,
        RuntimeError,
        ValueError,
        TimeoutError,
    ) as error:
        print(f"pi-git-sign: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
