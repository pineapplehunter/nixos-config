"""Small xdg-desktop-portal clients used inside the Pi sandbox."""

import argparse
import asyncio
import os
import secrets
import signal
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

from dbus_next import DBusError, Message, MessageType, Variant
from dbus_next.aio import MessageBus

BUS = "org.freedesktop.portal.Desktop"
DESKTOP_PATH = "/org/freedesktop/portal/desktop"
REQUEST_IFACE = "org.freedesktop.portal.Request"


class PortalError(RuntimeError):
    pass


class Cancelled(PortalError):
    pass


async def request_async(
    interface: str,
    method: str,
    parameters: tuple,
    token: str,
    timeout: int,
) -> dict[str, object]:
    connection = MessageBus()
    loop = asyncio.get_running_loop()
    responses = asyncio.Queue()
    installed_signals = []
    handle = None

    async def call(message, seconds):
        reply = await asyncio.wait_for(connection.call(message), seconds)
        if reply.message_type == MessageType.ERROR:
            raise DBusError._from_message(reply)
        return reply

    def on_response(message):
        if (
            message.message_type == MessageType.SIGNAL
            and message.interface == REQUEST_IFACE
            and message.member == "Response"
            and message.signature == "ua{sv}"
        ):
            responses.put_nowait(message)

    async def close():
        if handle is not None:
            try:
                await call(
                    Message(
                        destination=BUS,
                        path=handle,
                        interface=REQUEST_IFACE,
                        member="Close",
                    ),
                    2,
                )
            except (DBusError, OSError, TimeoutError):
                pass

    task = asyncio.current_task()
    try:
        await connection.connect()
        sender = connection.unique_name.lstrip(":").replace(".", "_")
        handle = f"{DESKTOP_PATH}/request/{sender}/{token}"
        connection.add_message_handler(on_response)
        # Subscribe before calling, buffering changed handles too: portals
        # may emit Response before returning the actual handle.
        await call(
            Message(
                destination="org.freedesktop.DBus",
                path="/org/freedesktop/DBus",
                interface="org.freedesktop.DBus",
                member="AddMatch",
                signature="s",
                body=[
                    f"type='signal',sender='{BUS}',"
                    f"interface='{REQUEST_IFACE}',member='Response',"
                    f"path_namespace='{DESKTOP_PATH}/request'"
                ],
            ),
            10,
        )
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, task.cancel)
            installed_signals.append(sig)
        reply = await call(
            Message(
                destination=BUS,
                path=DESKTOP_PATH,
                interface=interface,
                member=method,
                signature="ssa{sv}",
                body=list(parameters),
            ),
            10,
        )
        handle = reply.body[0]

        async def response():
            while True:
                message = await responses.get()
                if message.path == handle and message.sender == reply.sender:
                    return message.body

        try:
            code, results = await asyncio.wait_for(response(), timeout)
        except TimeoutError:
            await close()
            raise TimeoutError("portal request timed out") from None
        if code == 1:
            raise Cancelled("portal request cancelled by the user")
        if code != 0:
            raise PortalError(
                f"portal request failed with response code {code}"
            )
        return {key: value.value for key, value in results.items()}
    except asyncio.CancelledError:
        await close()
        raise Cancelled("portal request cancelled") from None
    finally:
        for sig in installed_signals:
            loop.remove_signal_handler(sig)
        connection.remove_message_handler(on_response)
        connected = connection.connected
        connection.disconnect()
        if connected:
            await connection.wait_for_disconnect()


def request(interface, method, parameters, token, timeout):
    return asyncio.run(
        request_async(interface, method, parameters, token, timeout)
    )


def choose_file(
    title: str, timeout: int, directory: bool, writable: bool
) -> str:
    token = "pi_" + secrets.token_hex(16)
    results = request(
        "org.freedesktop.portal.FileChooser",
        "OpenFile",
        (
            "",
            title,
            {
                "handle_token": Variant("s", token),
                "multiple": Variant("b", False),
                "directory": Variant("b", directory),
            },
        ),
        token,
        timeout,
    )
    uris = results.get("uris", [])
    item = "folder" if directory else "file"
    if len(uris) != 1:
        raise PortalError(f"the portal did not return exactly one {item}")
    parsed = urlparse(uris[0])
    if parsed.scheme != "file" or parsed.netloc not in {"", "localhost"}:
        raise PortalError("the portal returned a non-file URI")

    path = Path(unquote(parsed.path)).resolve(strict=True)
    documents = Path("/run/flatpak/doc")
    try:
        relative = path.relative_to(documents)
    except ValueError as error:
        raise PortalError(
            "the portal returned a path outside Pi's Documents view"
        ) from error

    if writable:
        path = (Path("/run/flatpak/doc-rw") / relative).resolve(strict=True)
    if directory and not path.is_dir():
        raise PortalError("the selected document is not a directory")
    if not directory and not path.is_file():
        raise PortalError("the selected document is not a regular file")
    if writable and not os.access(path, os.W_OK):
        raise PortalError(
            f"the portal did not grant write access to the selected {item}"
        )
    return str(path)


def main() -> int:
    command = Path(sys.argv[0]).name
    parser = argparse.ArgumentParser(prog=command)
    parser.add_argument("--timeout", type=int, default=120)
    if command != "pi-choose-file":
        parser.error(f"unknown command name: {command}")
    parser.add_argument("--title")
    parser.add_argument("--directory", action="store_true")
    parser.add_argument("--writable", action="store_true")
    args = parser.parse_args()
    try:
        if not Path("/.flatpak-info").is_file():
            raise PortalError(
                "Pi has no desktop portal identity; restart Pi after "
                "activating the updated Home Manager generation"
            )
        title = args.title or (
            "Choose a folder for Pi"
            if args.directory
            else "Choose a file for Pi"
        )
        print(choose_file(title, args.timeout, args.directory, args.writable))
        return 0
    except Cancelled as error:
        print(error, file=sys.stderr)
        return 2
    except TimeoutError as error:
        print(error, file=sys.stderr)
        return 124
    except (PortalError, DBusError, OSError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
