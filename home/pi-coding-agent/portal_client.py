"""Small xdg-desktop-portal clients used inside the Pi sandbox."""

import argparse
import os
import secrets
import signal
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLibUnix", "2.0")
from gi.repository import Gio, GLib, GLibUnix  # noqa: E402

BUS = "org.freedesktop.portal.Desktop"
DESKTOP_PATH = "/org/freedesktop/portal/desktop"
REQUEST_IFACE = "org.freedesktop.portal.Request"


class PortalError(RuntimeError):
    pass


class Cancelled(PortalError):
    pass


def request(
    interface: str,
    method: str,
    parameters: GLib.Variant,
    token: str,
    timeout: int,
) -> dict[str, object]:
    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    sender = connection.get_unique_name().lstrip(":").replace(".", "_")
    expected = f"{DESKTOP_PATH}/request/{sender}/{token}"
    loop = GLib.MainLoop()
    response: list[tuple[int, dict[str, object]]] = []

    def on_response(
        _connection, _sender, _path, _iface, _signal, params, _data=None
    ):
        code, results = params.unpack()
        response.append((code, results))
        loop.quit()

    subscription = connection.signal_subscribe(
        BUS,
        REQUEST_IFACE,
        "Response",
        expected,
        None,
        Gio.DBusSignalFlags.NONE,
        on_response,
        None,
    )
    handle = expected
    try:
        reply = connection.call_sync(
            BUS,
            DESKTOP_PATH,
            interface,
            method,
            parameters,
            GLib.VariantType.new("(o)"),
            Gio.DBusCallFlags.NONE,
            10_000,
            None,
        )
        handle = reply.unpack()[0]
        if handle != expected:
            connection.signal_unsubscribe(subscription)
            subscription = connection.signal_subscribe(
                BUS,
                REQUEST_IFACE,
                "Response",
                handle,
                None,
                Gio.DBusSignalFlags.NONE,
                on_response,
                None,
            )

        timed_out = [False]
        timeout_id = GLib.timeout_add_seconds(
            timeout,
            lambda: (timed_out.__setitem__(0, True), loop.quit(), False)[2],
        )
        signal_ids = [
            GLibUnix.signal_add(
                GLib.PRIORITY_DEFAULT, sig, lambda: (loop.quit(), False)[1]
            )
            for sig in (signal.SIGINT, signal.SIGTERM)
        ]
        loop.run()
        if timeout_id:
            GLib.source_remove(timeout_id)
        for source_id in signal_ids:
            if source_id:
                GLib.source_remove(source_id)

        if not response:
            try:
                connection.call_sync(
                    BUS,
                    handle,
                    REQUEST_IFACE,
                    "Close",
                    None,
                    None,
                    Gio.DBusCallFlags.NONE,
                    2_000,
                    None,
                )
            except GLib.Error:
                pass
            if timed_out[0]:
                raise TimeoutError("portal request timed out")
            raise Cancelled("portal request cancelled")
        code, results = response[0]
        if code == 1:
            raise Cancelled("portal request cancelled by the user")
        if code != 0:
            raise PortalError(
                f"portal request failed with response code {code}"
            )
        return results
    finally:
        connection.signal_unsubscribe(subscription)


def open_uri(uri: str, timeout: int) -> None:
    parsed = urlparse(uri)
    if parsed.scheme.lower() == "file":
        raise PortalError("file:// URIs are not accepted")
    if parsed.scheme.lower() not in {"http", "https"}:
        raise PortalError("only http:// and https:// URIs are accepted")
    token = "pi_" + secrets.token_hex(16)
    request(
        "org.freedesktop.portal.OpenURI",
        "OpenURI",
        GLib.Variant(
            "(ssa{sv})", ("", uri, {"handle_token": GLib.Variant("s", token)})
        ),
        token,
        timeout,
    )


def choose_file(
    title: str, timeout: int, directory: bool, writable: bool
) -> str:
    token = "pi_" + secrets.token_hex(16)
    results = request(
        "org.freedesktop.portal.FileChooser",
        "OpenFile",
        GLib.Variant(
            "(ssa{sv})",
            (
                "",
                title,
                {
                    "handle_token": GLib.Variant("s", token),
                    "multiple": GLib.Variant("b", False),
                    "directory": GLib.Variant("b", directory),
                },
            ),
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
    if command == "pi-open-uri":
        parser.add_argument("uri")
    elif command == "pi-choose-file":
        parser.add_argument("--title")
        parser.add_argument("--directory", action="store_true")
        parser.add_argument("--writable", action="store_true")
    else:
        parser.error(f"unknown command name: {command}")
    args = parser.parse_args()
    try:
        if not Path("/.flatpak-info").is_file():
            raise PortalError(
                "Pi has no desktop portal identity; restart Pi after "
                "activating the updated Home Manager generation"
            )
        if command == "pi-open-uri":
            open_uri(args.uri, args.timeout)
        else:
            title = args.title or (
                "Choose a folder for Pi"
                if args.directory
                else "Choose a file for Pi"
            )
            print(
                choose_file(
                    title, args.timeout, args.directory, args.writable
                )
            )
        return 0
    except Cancelled as error:
        print(error, file=sys.stderr)
        return 2
    except TimeoutError as error:
        print(error, file=sys.stderr)
        return 124
    except (PortalError, GLib.Error, OSError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
