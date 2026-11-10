"""Host-side one-way clipboard broker for sandboxed Pi sessions."""

import argparse
import asyncio
import subprocess
import sys
import tempfile

from dbus_next import DBusError, NameFlag, RequestNameReply
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method

BUS_NAME = "io.github.pineapplehunter.LocalClipboard1"
OBJECT_PATH = "/io/github/pineapplehunter/LocalClipboard1"
MAX_CLIPBOARD_BYTES = 8 * 1024 * 1024


class Clipboard(ServiceInterface):
    def __init__(self, wl_copy):
        super().__init__(BUS_NAME)
        self.wl_copy = wl_copy

    @method()
    async def Copy(self, content: "ay"):  # noqa: F821
        if len(content) > MAX_CLIPBOARD_BYTES:
            raise DBusError(
                BUS_NAME + ".Error.TooLarge", "clipboard content exceeds 8 MiB"
            )
        try:
            content.decode("utf-8")
        except UnicodeDecodeError:
            raise DBusError(
                BUS_NAME + ".Error.InvalidText",
                "clipboard content is not valid UTF-8 text",
            ) from None
        # A background selection owner inherits stderr: a pipe would hang
        # communicate() after the original wl-copy process has exited.
        with tempfile.TemporaryFile() as stderr:
            process = None
            try:
                process = await asyncio.create_subprocess_exec(
                    self.wl_copy,
                    "--type",
                    "text/plain;charset=utf-8",
                    stdin=subprocess.PIPE,
                    stderr=stderr,
                )
                await asyncio.wait_for(process.communicate(content), 4)
                if process.returncode:
                    stderr.seek(0)
                    detail = (
                        stderr.read().decode("utf-8", errors="replace").strip()
                    )
                    raise DBusError(
                        BUS_NAME + ".Error.CopyFailed",
                        detail or "wl-copy failed",
                    )
            except (TimeoutError, OSError) as error:
                if process is not None and process.returncode is None:
                    process.kill()
                    await process.wait()
                detail = (
                    "wl-copy timed out"
                    if isinstance(error, TimeoutError)
                    else str(error)
                )
                raise DBusError(
                    BUS_NAME + ".Error.CopyFailed", detail
                ) from None
            except asyncio.CancelledError:
                if process is not None and process.returncode is None:
                    process.kill()
                    await process.wait()
                raise


async def serve(wl_copy):
    connection = MessageBus()
    try:
        await connection.connect()
        connection.export(OBJECT_PATH, Clipboard(wl_copy))
        ownership = await connection.request_name(
            BUS_NAME, NameFlag.DO_NOT_QUEUE
        )
        if ownership != RequestNameReply.PRIMARY_OWNER:
            raise RuntimeError(f"could not own {BUS_NAME}: {ownership.name}")
        await connection.wait_for_disconnect()
    finally:
        connection.unexport(OBJECT_PATH)
        connected = connection.connected
        connection.disconnect()
        if connected:
            await connection.wait_for_disconnect()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wl-copy", required=True)
    args = parser.parse_args()
    try:
        asyncio.run(serve(args.wl_copy))
        return 0
    except (DBusError, OSError, RuntimeError) as error:
        print(f"pi-clipboardd: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
