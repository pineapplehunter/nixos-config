import argparse
import asyncio
import pathlib
import signal
import sys

from dbus_next import DBusError, NameFlag, RequestNameReply
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method

from notification import (
    BUS_NAME,
    INTERFACE,
    OBJECT_PATH,
    ValidationError,
    send_discord,
)

IDLE_TIMEOUT_SECONDS = 30


async def serve(webhook_url: str) -> None:
    bus = MessageBus()
    loop = asyncio.get_running_loop()
    stopped = asyncio.Event()
    idle_handle = None
    active = 0
    # Preserve the original serial delivery behavior without blocking D-Bus.
    delivery_lock = asyncio.Lock()

    def reset_idle_timeout():
        nonlocal idle_handle
        if idle_handle is not None:
            idle_handle.cancel()
        idle_handle = loop.call_later(IDLE_TIMEOUT_SECONDS, stopped.set)

    class NotificationService(ServiceInterface):
        def __init__(self):
            super().__init__(INTERFACE)

        @method()
        async def Notify(self, username: 's', icon: 's', title: 's',
                         content: 's', color: 's'):
            nonlocal active
            active += 1
            if idle_handle is not None:
                idle_handle.cancel()
            try:
                async with delivery_lock:
                    await asyncio.to_thread(
                        send_discord,
                        webhook_url, username, icon, title, content, color,
                    )
            except ValidationError as error:
                raise DBusError(
                    BUS_NAME + ".Error.InvalidArgument", str(error)
                ) from error
            except Exception as error:
                raise DBusError(
                    BUS_NAME + ".Error.DeliveryFailed", str(error)
                ) from error
            finally:
                active -= 1
                if not active:
                    reset_idle_timeout()

    tasks = []
    signals = []
    try:
        await bus.connect()
        bus.export(OBJECT_PATH, NotificationService())
        reply = await bus.request_name(BUS_NAME, NameFlag.DO_NOT_QUEUE)
        if reply != RequestNameReply.PRIMARY_OWNER:
            raise RuntimeError(f"could not acquire D-Bus name {BUS_NAME}: {reply.name}")
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, stopped.set)
            signals.append(sig)
        reset_idle_timeout()
        stop_task = asyncio.create_task(stopped.wait())
        disconnect_task = asyncio.create_task(bus.wait_for_disconnect())
        tasks = [stop_task, disconnect_task]
        done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        if disconnect_task in done:
            await disconnect_task
    finally:
        for sig in signals:
            loop.remove_signal_handler(sig)
        if idle_handle is not None:
            idle_handle.cancel()
        bus.unexport(OBJECT_PATH)
        connected = bus.connected
        bus.disconnect()
        try:
            if connected:
                await bus.wait_for_disconnect()
        finally:
            for task in tasks:
                task.cancel()
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
            # dbus-next 0.2.3 shuts down, but does not close, these handles.
            bus._stream.close()
            bus._sock.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--webhook-file", required=True)
    args = parser.parse_args()

    try:
        webhook_url = pathlib.Path(args.webhook_file).read_text().strip()
        if not webhook_url:
            raise RuntimeError("webhook file is empty")
        asyncio.run(serve(webhook_url))
        return 0
    except (DBusError, OSError, RuntimeError, EOFError) as error:
        print(f"local-notifyd: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
