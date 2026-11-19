"""Sandbox gh shim for pi-web-access."""

import asyncio
import os
import re
import sys

from dbus_next import DBusError, Message, MessageType
from dbus_next.aio import MessageBus

BUS_NAME = "io.github.pineapplehunter.GitHubFetch1"
OBJECT_PATH = "/io/github/pineapplehunter/GitHubFetch1"
GIT_PROGRAM = "@GIT@"


async def run_remote(args):
    connection = await MessageBus().connect()
    try:
        reply = await connection.call(
            Message(
                destination=BUS_NAME,
                path=OBJECT_PATH,
                interface=BUS_NAME,
                member="Run",
                signature="as",
                body=[args],
            )
        )
        if reply.message_type == MessageType.ERROR:
            raise DBusError._from_message(reply)
        return reply.body
    finally:
        connection.disconnect()
        await connection.wait_for_disconnect()


def main(args):
    if args == ["--version"]:
        print("gh version (Pi GitHub fetch shim)")
        return 0
    if args[:2] == ["repo", "clone"]:
        # Preserve public clones without sending a destination to the host.
        if (
            len(args) not in (8, 10)
            or not re.fullmatch(r"[a-zA-Z0-9-]+/[a-zA-Z0-9._-]+", args[2])
            or args[4:8] != ["--", "--depth", "1", "--single-branch"]
            or (len(args) == 10 and args[8] != "--branch")
        ):
            print("gh: unsupported clone invocation", file=sys.stderr)
            return 1
        branch = ["--branch=" + args[9]] if len(args) == 10 else []
        os.execv(
            GIT_PROGRAM,
            [
                GIT_PROGRAM,
                "clone",
                "--depth",
                "1",
                "--single-branch",
                *branch,
                "--",
                f"https://github.com/{args[2]}.git",
                args[3],
            ],
        )
    try:
        code, stdout, stderr = asyncio.run(
            asyncio.wait_for(run_remote(args), 17)
        )
        sys.stdout.buffer.write(stdout)
        sys.stderr.buffer.write(stderr)
        return code
    except (DBusError, OSError, TimeoutError) as error:
        print(f"gh: {error or 'GitHub fetch timed out'}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
