"""Host-only launcher. Backend commands and credentials never come from clients."""

import argparse
import asyncio
import logging
import os
import signal
from contextlib import suppress
from uuid import uuid4

from dbus_next import Message, MessageType, NameFlag, RequestNameReply
from dbus_next.aio import MessageBus

from . import INTERFACE, MAX_MESSAGE_BYTES, OBJECT_PATH, POLL_SECONDS

LOG = logging.getLogger(__name__)


class Session:
    def __init__(self, owner, process):
        self.owner = owner
        self.process = process
        self.messages = asyncio.Queue(maxsize=8)
        self.send_lock = asyncio.Lock()
        self.receive_lock = asyncio.Lock()
        self.reader = asyncio.create_task(self.read())

    async def read(self):
        try:
            while line := await self.process.stdout.readline():
                if len(line) > MAX_MESSAGE_BYTES or not line.endswith(b"\n"):
                    break
                await self.messages.put(line.decode("utf-8").rstrip("\n"))
        except (ValueError, UnicodeError, OSError):
            LOG.warning("Backend emitted an invalid or oversized MCP message")
        finally:
            if not asyncio.current_task().cancelling():
                await self.messages.put(None)

    async def close(self):
        self.reader.cancel()
        with suppress(asyncio.CancelledError):
            await self.reader
        # Terminate the entire backend group, including children of wrappers.
        with suppress(ProcessLookupError):
            os.killpg(self.process.pid, signal.SIGTERM)
        try:
            await asyncio.wait_for(self.process.wait(), 3)
        except TimeoutError:
            with suppress(ProcessLookupError):
                os.killpg(self.process.pid, signal.SIGKILL)
            await self.process.wait()


class Host:
    def __init__(self, command):
        self.command = command
        self.sessions = {}
        self.tasks = set()
        self.open_lock = asyncio.Lock()
        self.stopping = False

    def task(self, coroutine):
        task = asyncio.create_task(coroutine)
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)

    def handle(self, message):
        if (
            message.message_type == MessageType.SIGNAL
            and message.sender == "org.freedesktop.DBus"
            and message.interface == "org.freedesktop.DBus"
            and message.member == "NameOwnerChanged"
        ):
            name, _old, new = message.body
            if name.startswith(":") and not new:
                for identifier, session in list(self.sessions.items()):
                    if session.owner == name:
                        self.sessions.pop(identifier)
                        self.task(session.close())
            return
        if (
            message.message_type != MessageType.METHOD_CALL
            or message.path != OBJECT_PATH
        ):
            return
        if message.interface != INTERFACE:
            return Message.new_error(
                message, INTERFACE + ".UnknownMethod", "Unknown interface"
            )
        if not self.stopping:
            self.task(self.reply(message))
        return True

    async def reply(self, message):
        try:
            signature, body = await self.invoke(message)
            reply = Message.new_method_return(message, signature, body)
        except Exception:  # noqa: BLE001 - sanitize the transport boundary
            # Do not send exception text, configuration, or stderr across the bus.
            reply = Message.new_error(
                message,
                INTERFACE + ".Unavailable",
                "MCP session unavailable or request invalid",
            )
        await self.bus.send(reply)

    async def invoke(self, message):
        member, body = message.member, message.body
        if member == "Open" and message.signature == "":
            async with self.open_lock:
                if (
                    len(self.sessions) >= 64
                    or sum(s.owner == message.sender for s in self.sessions.values())
                    >= 16
                ):
                    raise ValueError("Session limit")
                process = await asyncio.create_subprocess_exec(
                    *self.command,
                    stdin=asyncio.subprocess.PIPE,
                    stdout=asyncio.subprocess.PIPE,
                    # stderr is inherited by journald, never forwarded to clients.
                    cwd="/",
                    start_new_session=True,
                    limit=MAX_MESSAGE_BYTES + 1,
                )
                identifier = uuid4().hex
                session = Session(message.sender, process)
                self.sessions[identifier] = session
                owner = await self.bus.call(
                    Message(
                        destination="org.freedesktop.DBus",
                        path="/org/freedesktop/DBus",
                        interface="org.freedesktop.DBus",
                        member="NameHasOwner",
                        signature="s",
                        body=[message.sender],
                    )
                )
                if not owner.body[0]:
                    if self.sessions.pop(identifier, None) is not None:
                        await session.close()
                    raise EOFError
                return "s", [identifier]
        signatures = {"Send": "ss", "Receive": "s", "Close": "s"}
        if member not in signatures or message.signature != signatures[member]:
            raise ValueError("Unknown method or signature")
        session = self.sessions[body[0]]
        if session.owner != message.sender:
            raise ValueError("Session belongs to another connection")
        if member == "Send":
            payload = body[1].encode("utf-8")
            if not payload or len(payload) > MAX_MESSAGE_BYTES or b"\n" in payload:
                raise ValueError("Invalid stdio frame")
            async with session.send_lock:
                session.process.stdin.write(payload + b"\n")
                await asyncio.wait_for(session.process.stdin.drain(), 30)
            return "", []
        if member == "Receive":
            async with session.receive_lock:
                try:
                    payload = await asyncio.wait_for(
                        session.messages.get(), POLL_SECONDS
                    )
                except TimeoutError:
                    payload = ""  # Empty long poll, not an MCP message.
                if payload is None:
                    # Keep EOF visible to any subsequent Receive call.
                    session.messages.put_nowait(None)
                    raise EOFError
                return "s", [payload]
        self.sessions.pop(body[0])
        await session.close()
        return "", []

    async def run(self, name):
        self.bus = await MessageBus().connect()
        self.bus.add_message_handler(self.handle)
        try:
            reply = await self.bus.call(
                Message(
                    destination="org.freedesktop.DBus",
                    path="/org/freedesktop/DBus",
                    interface="org.freedesktop.DBus",
                    member="AddMatch",
                    signature="s",
                    body=[
                        "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged'"
                    ],
                )
            )
            if reply.message_type == MessageType.ERROR:
                raise RuntimeError("Cannot monitor client lifetimes")
            if (
                await self.bus.request_name(name, NameFlag.DO_NOT_QUEUE)
                != RequestNameReply.PRIMARY_OWNER
            ):
                raise RuntimeError("Bus name already owned")
            stop = asyncio.Event()
            loop = asyncio.get_running_loop()
            for sig in (signal.SIGTERM, signal.SIGINT):
                loop.add_signal_handler(sig, stop.set)
            disconnected = asyncio.create_task(self.bus.wait_for_disconnect())
            stopped = asyncio.create_task(stop.wait())
            try:
                await asyncio.wait(
                    [disconnected, stopped], return_when=asyncio.FIRST_COMPLETED
                )
            finally:
                disconnected.cancel()
                stopped.cancel()
        finally:
            self.stopping = True
            for task in list(self.tasks):
                task.cancel()
            await asyncio.gather(*self.tasks, return_exceptions=True)
            await asyncio.gather(*(s.close() for s in self.sessions.values()))
            self.bus.disconnect()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--service", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("a fixed backend command is required after --")
    logging.basicConfig(level=logging.INFO)
    try:
        asyncio.run(Host(command).run(args.service))
    except Exception:  # noqa: BLE001 - do not log backend configuration
        LOG.error("MCP host failed; check host service configuration")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
