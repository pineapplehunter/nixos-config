"""Host-side one-way clipboard broker for sandboxed Pi sessions."""

import argparse
import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS_NAME = "io.github.pineapplehunter.LocalClipboard1"
INTERFACE = BUS_NAME
OBJECT_PATH = "/io/github/pineapplehunter/LocalClipboard1"
MAX_CLIPBOARD_BYTES = 8 * 1024 * 1024
INTROSPECTION_XML = f"""
<node>
  <interface name="{INTERFACE}">
    <method name="Copy">
      <arg name="content" type="ay" direction="in"/>
    </method>
  </interface>
</node>
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wl-copy", required=True)
    args = parser.parse_args()

    try:
        connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        loop = GLib.MainLoop()

        def method_call(
            _connection,
            _sender,
            _object_path,
            _interface_name,
            method_name,
            parameters,
            invocation,
        ) -> None:
            if method_name != "Copy":
                invocation.return_dbus_error(
                    BUS_NAME + ".Error.UnknownMethod", "unknown method"
                )
                return

            content = bytes(parameters.unpack()[0])
            if len(content) > MAX_CLIPBOARD_BYTES:
                invocation.return_dbus_error(
                    BUS_NAME + ".Error.TooLarge",
                    "clipboard content exceeds 8 MiB",
                )
                return

            try:
                content.decode("utf-8")
                subprocess.run(
                    [
                        args.wl_copy,
                        "--type",
                        "text/plain;charset=utf-8",
                    ],
                    input=content,
                    check=True,
                    stderr=subprocess.PIPE,
                    timeout=4,
                )
                invocation.return_value(None)
            except UnicodeDecodeError:
                invocation.return_dbus_error(
                    BUS_NAME + ".Error.InvalidText",
                    "clipboard content is not valid UTF-8 text",
                )
            except subprocess.TimeoutExpired:
                invocation.return_dbus_error(
                    BUS_NAME + ".Error.CopyFailed", "wl-copy timed out"
                )
            except subprocess.CalledProcessError as error:
                detail = error.stderr.decode("utf-8", errors="replace").strip()
                invocation.return_dbus_error(
                    BUS_NAME + ".Error.CopyFailed",
                    detail or "wl-copy failed",
                )

        node_info = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML)
        connection.register_object(
            OBJECT_PATH,
            node_info.interfaces[0],
            method_call,
            None,
            None,
        )
        result = connection.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "RequestName",
            GLib.Variant("(su)", (BUS_NAME, 4)),
            GLib.VariantType.new("(u)"),
            Gio.DBusCallFlags.NONE,
            -1,
            None,
        )
        if result.unpack()[0] != 1:
            raise RuntimeError("clipboard bus name is already owned")

        loop.run()
        return 0
    except (GLib.Error, OSError, RuntimeError) as error:
        print(f"pi-clipboardd: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
