"""Host-side one-way clipboard broker for sandboxed Pi sessions."""

import argparse
import subprocess
import sys
import tempfile

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

BUS_NAME = "io.github.pineapplehunter.LocalClipboard1"
OBJECT_PATH = "/io/github/pineapplehunter/LocalClipboard1"
MAX_CLIPBOARD_BYTES = 8 * 1024 * 1024


class Clipboard(dbus.service.Object):
    def __init__(self, bus_name, wl_copy):
        super().__init__(bus_name, OBJECT_PATH)
        self.wl_copy = wl_copy

    @dbus.service.method(
        BUS_NAME, in_signature="ay", out_signature="", byte_arrays=True
    )
    def Copy(self, content):
        content = bytes(content)
        if len(content) > MAX_CLIPBOARD_BYTES:
            raise dbus.DBusException(
                "clipboard content exceeds 8 MiB",
                name=BUS_NAME + ".Error.TooLarge",
            )

        try:
            content.decode("utf-8")
            # wl-copy's background selection owner inherits stderr. A pipe
            # would make communicate() wait for that owner to exit, even
            # after the original process has set the clipboard.
            with tempfile.TemporaryFile() as stderr:
                result = subprocess.run(
                    [self.wl_copy, "--type", "text/plain;charset=utf-8"],
                    input=content,
                    stderr=stderr,
                    timeout=4,
                )
                if result.returncode:
                    stderr.seek(0)
                    detail = stderr.read().decode(
                        "utf-8", errors="replace"
                    ).strip()
                    raise dbus.DBusException(
                        detail or "wl-copy failed",
                        name=BUS_NAME + ".Error.CopyFailed",
                    )
        except UnicodeDecodeError:
            raise dbus.DBusException(
                "clipboard content is not valid UTF-8 text",
                name=BUS_NAME + ".Error.InvalidText",
            ) from None
        except (subprocess.TimeoutExpired, OSError) as error:
            detail = (
                "wl-copy timed out"
                if isinstance(error, subprocess.TimeoutExpired)
                else str(error)
            )
            raise dbus.DBusException(
                detail, name=BUS_NAME + ".Error.CopyFailed"
            ) from None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wl-copy", required=True)
    args = parser.parse_args()

    try:
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        connection = dbus.SessionBus()
        bus_name = dbus.service.BusName(
            BUS_NAME, bus=connection, do_not_queue=True
        )
        clipboard = Clipboard(bus_name, args.wl_copy)
        try:
            GLib.MainLoop().run()
        finally:
            clipboard.remove_from_connection()
        return 0
    except (dbus.DBusException, GLib.Error, OSError, RuntimeError) as error:
        print(f"pi-clipboardd: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
