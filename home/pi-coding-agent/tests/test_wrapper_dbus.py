"""Run with PI_WRAPPER_TEST_PRIVATE_BUS=1 under dbus-run-session."""

import asyncio
import os
from pathlib import Path
import signal
import sys
import tempfile
import unittest

from dbus_next import DBusError, Message, NameFlag, Variant
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method

WRAPPER = Path(__file__).resolve().parents[1] / "pineapplehunter/wrapper"
sys.path.insert(0, str(WRAPPER))
import clipboard_client as client  # noqa: E402
import clipboard_daemon as daemon  # noqa: E402
import portal_client as portal  # noqa: E402
import wrapping  # noqa: E402


class Portal(ServiceInterface):
    def __init__(self, bus):
        super().__init__("org.freedesktop.portal.FileChooser")
        self.bus = bus
        self.code = 0
        self.mode = "early"
        self.entered = asyncio.Event()
        self.handle = portal.DESKTOP_PATH + "/request/changed/handle"

    @method()
    def OpenFile(  # noqa: F722
        self,
        parent: "s",  # noqa: F821
        title: "s",  # noqa: F821
        options: "a{sv}",  # noqa: F722
    ) -> "o":  # noqa: F821
        assert parent == "" and title == "test"
        assert options["handle_token"].signature == "s"
        self.entered.set()
        if self.mode == "error":
            raise DBusError("org.example.NamedError", "named failure")
        if self.mode == "early":
            self.bus.send(
                Message.new_signal(
                    self.handle,
                    portal.REQUEST_IFACE,
                    "Response",
                    "ua{sv}",
                    [self.code, {"uris": Variant("as", ["file:///test"])}],
                )
            )
        return self.handle


class Request(ServiceInterface):
    def __init__(self):
        super().__init__(portal.REQUEST_IFACE)
        self.closed = asyncio.Event()

    @method()
    def Close(self):
        self.closed.set()


class Documents(ServiceInterface):
    def __init__(self):
        super().__init__("org.freedesktop.portal.Documents")

    @method()
    def GetMountPoint(self) -> "ay":  # noqa: F821
        return b"/mock/documents\0"


class Roundtrip(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        # The caller must create a private bus; never discover a desktop bus.
        self.assertTrue(os.environ.get("PI_WRAPPER_TEST_PRIVATE_BUS"))
        self.bus = await MessageBus().connect()
        self.temp = tempfile.TemporaryDirectory()
        self.copy_path = Path(self.temp.name) / "wl-copy"
        self.content_path = Path(self.temp.name) / "content"
        self.write_copy(
            "import pathlib,sys\n"
            f"pathlib.Path({str(self.content_path)!r}).write_bytes("
            "sys.stdin.buffer.read())\n"
        )
        self.clipboard = daemon.Clipboard(str(self.copy_path))
        self.bus.export(daemon.OBJECT_PATH, self.clipboard)
        await self.bus.request_name(daemon.BUS_NAME, NameFlag.DO_NOT_QUEUE)
        self.portal = Portal(self.bus)
        self.request = Request()
        self.bus.export(portal.DESKTOP_PATH, self.portal)
        self.bus.export(self.portal.handle, self.request)
        await self.bus.request_name(portal.BUS, NameFlag.DO_NOT_QUEUE)
        self.bus.export("/org/freedesktop/portal/documents", Documents())
        await self.bus.request_name(
            "org.freedesktop.portal.Documents", NameFlag.DO_NOT_QUEUE
        )

    async def asyncTearDown(self):
        self.bus.disconnect()
        await self.bus.wait_for_disconnect()
        self.temp.cleanup()

    def write_copy(self, body):
        self.copy_path.write_text(f"#!{sys.executable}\n" + body)
        self.copy_path.chmod(0o755)

    async def clipboard_error(self, data, suffix):
        with self.assertRaises(DBusError) as caught:
            await client.copy(data)
        self.assertEqual(
            caught.exception.type, daemon.BUS_NAME + ".Error." + suffix
        )

    async def test_clipboard_roundtrip_and_validation(self):
        await client.copy("clipboard ✓".encode())
        self.assertEqual(self.content_path.read_text(), "clipboard ✓")
        await self.clipboard_error(b"\xff", "InvalidText")
        await self.clipboard_error(
            b"x" * (daemon.MAX_CLIPBOARD_BYTES + 1), "TooLarge"
        )
        await client.copy(b"x" * daemon.MAX_CLIPBOARD_BYTES)
        self.assertEqual(
            self.content_path.stat().st_size, daemon.MAX_CLIPBOARD_BYTES
        )

    async def test_clipboard_failure_and_timeout(self):
        self.write_copy(
            "import sys\nsys.stderr.write('mock copy failure')\nsys.exit(1)\n"
        )
        await self.clipboard_error(b"ok", "CopyFailed")
        self.write_copy("import time\ntime.sleep(20)\n")
        started = asyncio.get_running_loop().time()
        await self.clipboard_error(b"ok", "CopyFailed")
        self.assertLess(asyncio.get_running_loop().time() - started, 5)

    async def test_background_owner_stderr_does_not_hang(self):
        self.write_copy(
            "import os,time\nif os.fork() == 0:\n"
            " time.sleep(2)\n os._exit(0)\n"
        )
        await asyncio.wait_for(client.copy(b"ok"), 1)

    async def test_clipboard_cli(self):
        process = await asyncio.create_subprocess_exec(
            sys.executable,
            str(WRAPPER / "clipboard_client.py"),
            stdin=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        _, stderr = await asyncio.wait_for(process.communicate(b"CLI"), 5)
        self.assertEqual((process.returncode, stderr), (0, b""))
        self.assertEqual(self.content_path.read_bytes(), b"CLI")

    async def test_clipboard_cli_timeout(self):
        def swallow_copy(message):
            if (
                message.interface == daemon.BUS_NAME
                and message.member == "Copy"
            ):
                return True  # Deliberately leave the method unanswered.

        self.bus.add_message_handler(swallow_copy)
        try:
            process = await asyncio.create_subprocess_exec(
                sys.executable,
                str(WRAPPER / "clipboard_client.py"),
                stdin=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            started = asyncio.get_running_loop().time()
            _, stderr = await asyncio.wait_for(process.communicate(b"CLI"), 7)
            elapsed = asyncio.get_running_loop().time() - started
            self.assertEqual(process.returncode, 1)
            self.assertIn(b"wl-copy:", stderr)
            self.assertGreaterEqual(elapsed, 4.8)
            self.assertLess(elapsed, 6)
        finally:
            self.bus.remove_message_handler(swallow_copy)

    async def test_duplicate_clipboard_name_fails(self):
        with self.assertRaisesRegex(RuntimeError, "could not own"):
            await daemon.serve(str(self.copy_path))

    def parameters(self):
        return ("", "test", {"handle_token": Variant("s", "test")})

    async def request_portal(self, timeout=1):
        return await portal.request_async(
            self.portal.name,
            "OpenFile",
            self.parameters(),
            "test",
            timeout,
        )

    async def test_changed_handle_early_response(self):
        result = await self.request_portal()
        self.assertEqual(result, {"uris": ["file:///test"]})
        self.assertFalse(self.request.closed.is_set())

    async def test_portal_named_error(self):
        self.portal.mode = "error"
        with self.assertRaises(DBusError) as caught:
            await self.request_portal()
        self.assertEqual(caught.exception.type, "org.example.NamedError")

    async def test_portal_response_errors(self):
        self.portal.code = 1
        with self.assertRaises(portal.Cancelled):
            await self.request_portal()
        self.portal.code = 2
        with self.assertRaisesRegex(portal.PortalError, "response code 2"):
            await self.request_portal()

    async def test_portal_timeout_closes_changed_handle(self):
        self.portal.mode = "pending"
        with self.assertRaisesRegex(TimeoutError, "portal request timed out"):
            await self.request_portal(0.02)
        self.assertTrue(self.request.closed.is_set())

    async def test_portal_signal_closes_changed_handle(self):
        self.portal.mode = "pending"
        task = asyncio.create_task(self.request_portal())
        await self.portal.entered.wait()
        await asyncio.sleep(0.02)
        os.kill(os.getpid(), signal.SIGTERM)
        with self.assertRaises(portal.Cancelled):
            await task
        self.assertTrue(self.request.closed.is_set())

    async def test_spoofed_response_is_ignored(self):
        self.portal.mode = "pending"
        task = asyncio.create_task(self.request_portal(0.1))
        await self.portal.entered.wait()
        attacker = await MessageBus().connect()
        try:
            await attacker.send(
                Message.new_signal(
                    self.portal.handle,
                    portal.REQUEST_IFACE,
                    "Response",
                    "ua{sv}",
                    [0, {}],
                )
            )
            with self.assertRaises(TimeoutError):
                await task
        finally:
            attacker.disconnect()
            await attacker.wait_for_disconnect()

    async def test_document_mount(self):
        result = await asyncio.to_thread(wrapping.portal_mount)
        self.assertEqual(
            result, Path("/mock/documents/by-app") / wrapping.APP_ID
        )

    async def test_missing_bus_startup_propagates(self):
        old = os.environ["DBUS_SESSION_BUS_ADDRESS"]
        os.environ["DBUS_SESSION_BUS_ADDRESS"] = (
            "unix:path=/nonexistent/pi-test-bus"
        )
        try:
            with self.assertRaises(OSError):
                await client.copy(b"ok")
            with self.assertRaises(OSError):
                await daemon.serve(str(self.copy_path))
            with self.assertRaises(OSError):
                await self.request_portal()
        finally:
            os.environ["DBUS_SESSION_BUS_ADDRESS"] = old


if __name__ == "__main__":
    unittest.main()
