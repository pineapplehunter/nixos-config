import argparse
import pathlib
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

from notification import (
    BUS_NAME,
    INTERFACE,
    OBJECT_PATH,
    ValidationError,
    send_discord,
)

IDLE_TIMEOUT_SECONDS = 30
INTROSPECTION_XML = f"""
<node>
  <interface name="{INTERFACE}">
    <method name="Notify">
      <arg name="username" type="s" direction="in"/>
      <arg name="icon" type="s" direction="in"/>
      <arg name="title" type="s" direction="in"/>
      <arg name="content" type="s" direction="in"/>
      <arg name="color" type="s" direction="in"/>
    </method>
  </interface>
</node>
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--webhook-file", required=True)
    args = parser.parse_args()

    try:
        webhook_url = pathlib.Path(args.webhook_file).read_text().strip()
        if not webhook_url:
            raise RuntimeError("webhook file is empty")

        connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        loop = GLib.MainLoop()
        idle_source = 0

        def idle_timeout() -> bool:
            loop.quit()
            return GLib.SOURCE_REMOVE

        def reset_idle_timeout() -> None:
            nonlocal idle_source
            if idle_source:
                GLib.source_remove(idle_source)
            idle_source = GLib.timeout_add_seconds(
                IDLE_TIMEOUT_SECONDS, idle_timeout
            )

        def method_call(
            _connection,
            _sender,
            _object_path,
            _interface_name,
            method_name,
            parameters,
            invocation,
        ) -> None:
            if method_name != "Notify":
                invocation.return_dbus_error(
                    BUS_NAME + ".Error.UnknownMethod", "unknown method"
                )
                return
            username, icon, title, content, color = parameters.unpack()
            try:
                send_discord(
                    webhook_url, username, icon, title, content, color
                )
                invocation.return_value(None)
            except ValidationError as error:
                invocation.return_dbus_error(
                    BUS_NAME + ".Error.InvalidArgument", str(error)
                )
            except Exception as error:
                invocation.return_dbus_error(
                    BUS_NAME + ".Error.DeliveryFailed", str(error)
                )
            finally:
                reset_idle_timeout()

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
            raise RuntimeError("notification bus name is already owned")

        reset_idle_timeout()
        loop.run()
        return 0
    except (GLib.Error, OSError, RuntimeError) as error:
        print(f"local-notifyd: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
