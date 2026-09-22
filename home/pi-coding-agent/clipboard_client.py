"""One-way wl-copy compatibility client for Pi's clipboard broker."""

import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS_NAME = "io.github.pineapplehunter.LocalClipboard1"
INTERFACE = BUS_NAME
OBJECT_PATH = "/io/github/pineapplehunter/LocalClipboard1"
MAX_CLIPBOARD_BYTES = 8 * 1024 * 1024


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
        connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        connection.call_sync(
            BUS_NAME,
            OBJECT_PATH,
            INTERFACE,
            "Copy",
            GLib.Variant("(ay)", (list(data),)),
            None,
            Gio.DBusCallFlags.NONE,
            5_000,
            None,
        )
        return 0
    except (GLib.Error, RuntimeError, UnicodeDecodeError) as error:
        print(f"wl-copy: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
