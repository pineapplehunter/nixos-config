import argparse
import os
import pathlib
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

from notification import BUS_NAME, INTERFACE, OBJECT_PATH, ValidationError, validate


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--title", required=True)
    parser.add_argument("--content", required=True)
    parser.add_argument("--color", default="", help="Discord embed color in #RRGGBB form")
    args = parser.parse_args()

    try:
        validate(args.title, args.content, args.color)
        if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
            runtime_directory = os.environ.get("XDG_RUNTIME_DIR")
            if not runtime_directory:
                raise RuntimeError(
                    "neither DBUS_SESSION_BUS_ADDRESS nor XDG_RUNTIME_DIR is set"
                )
            os.environ["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=" + str(
                pathlib.Path(runtime_directory) / "bus"
            )

        connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        connection.call_sync(
            BUS_NAME,
            OBJECT_PATH,
            INTERFACE,
            "Notify",
            GLib.Variant("(sss)", (args.title, args.content, args.color)),
            None,
            Gio.DBusCallFlags.NONE,
            20_000,
            None,
        )
        return 0
    except (ValidationError, GLib.Error, RuntimeError) as error:
        print(f"local-notify: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
