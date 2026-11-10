"""D-Bus integration; package checks provide a private session bus."""

import asyncio
import http.server
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

from dbus_next import Message, MessageType
from dbus_next.aio import MessageBus

from notification import BUS_NAME, INTERFACE, OBJECT_PATH

ROOT = Path(__file__).resolve().parents[1]


class WebhookHandler(http.server.BaseHTTPRequestHandler):
    payloads = []
    status = 204

    def do_POST(self):
        self.payloads.append(
            json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        )
        self.send_response(self.status)
        self.end_headers()

    def log_message(self, *_args):
        pass


@unittest.skipUnless(
    os.environ.get("LOCAL_NOTIFY_TEST_BUS") == "1",
    "set LOCAL_NOTIFY_TEST_BUS=1 under a private dbus-run-session",
)
class DBusTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.bus = await MessageBus().connect()
        self.assertFalse(await self.has_owner())

    async def asyncTearDown(self):
        self.bus.disconnect()
        await self.bus.wait_for_disconnect()
        self.bus._stream.close()
        self.bus._sock.close()

    async def has_owner(self):
        reply = await self.bus.call(Message(
            destination="org.freedesktop.DBus",
            path="/org/freedesktop/DBus",
            interface="org.freedesktop.DBus",
            member="NameHasOwner", signature="s", body=[BUS_NAME],
        ))
        return reply.body[0]

    async def wait_for_owner(self):
        async def wait():
            while not await self.has_owner():
                await asyncio.sleep(0.02)
        await asyncio.wait_for(wait(), 5)

    async def notify(self, username="tester"):
        return await asyncio.wait_for(self.bus.call(Message(
            destination=BUS_NAME, path=OBJECT_PATH, interface=INTERFACE,
            member="Notify", signature="sssss",
            body=[username, "https://example.test/icon.png", "Test", "body", ""],
        )), 5)

    async def test_cli_to_mock_webhook(self):
        WebhookHandler.payloads = []
        WebhookHandler.status = 204
        webhook = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), WebhookHandler
        )
        threading.Thread(target=webhook.serve_forever, daemon=True).start()
        with tempfile.TemporaryDirectory() as directory:
            webhook_file = Path(directory) / "webhook"
            webhook_file.write_text(
                f"http://127.0.0.1:{webhook.server_port}/mock\n"
            )
            command = [
                sys.executable, str(ROOT / "local-notifyd.py"),
                "--webhook-file", str(webhook_file),
            ]
            daemon = subprocess.Popen(
                command, stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE, text=True,
            )
            try:
                await self.wait_for_owner()
                cli_command = [
                    sys.executable, str(ROOT / "local-notify.py"),
                    "--username", "tester",
                    "--icon", "https://example.test/icon.png",
                    "--title", "Test",
                    "--content", "Mock only",
                ]
                result = await asyncio.to_thread(
                    subprocess.run, cli_command,
                    capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(WebhookHandler.payloads), 1)
                payload = WebhookHandler.payloads[0]
                self.assertEqual(
                    payload["embeds"][0]["description"], "Mock only"
                )
                self.assertEqual(payload["username"], "tester")
                reply = await self.notify("")
                self.assertEqual(reply.message_type, MessageType.ERROR)
                self.assertEqual(
                    reply.error_name, BUS_NAME + ".Error.InvalidArgument"
                )
                self.assertEqual(len(WebhookHandler.payloads), 1)

                WebhookHandler.status = 503
                reply = await self.notify()
                self.assertEqual(reply.message_type, MessageType.ERROR)
                self.assertEqual(
                    reply.error_name, BUS_NAME + ".Error.DeliveryFailed"
                )
                result = await asyncio.to_thread(
                    subprocess.run, cli_command,
                    capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(result.returncode, 1)
                self.assertIn(BUS_NAME + ".Error.DeliveryFailed", result.stderr)
                result = await asyncio.to_thread(
                    subprocess.run, command,
                    capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(result.returncode, 1)
                self.assertIn("could not acquire D-Bus name", result.stderr)
                self.assertIsNone(daemon.poll())
            finally:
                daemon.terminate()
                try:
                    await asyncio.to_thread(daemon.wait, timeout=5)
                except subprocess.TimeoutExpired:
                    daemon.kill()
                    await asyncio.to_thread(daemon.wait, timeout=5)
                daemon.stderr.close()
                await asyncio.to_thread(webhook.shutdown)
                webhook.server_close()
        self.assertFalse(await self.has_owner())

    async def test_idle_timeout_and_cleanup(self):
        spec = importlib.util.spec_from_file_location(
            "local_notifyd", ROOT / "local-notifyd.py"
        )
        daemon = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(daemon)
        self.assertEqual(daemon.IDLE_TIMEOUT_SECONDS, 30)
        with (
            patch.object(daemon, "IDLE_TIMEOUT_SECONDS", 0.2),
            patch.object(daemon, "send_discord") as deliver,
        ):
            task = asyncio.create_task(daemon.serve("unused"))
            try:
                await self.wait_for_owner()
                await asyncio.sleep(0.1)
                reply = await self.notify()
                self.assertEqual(reply.message_type, MessageType.METHOD_RETURN)
                deliver.assert_called_once()
                await asyncio.sleep(0.12)
                self.assertFalse(task.done(), "delivery must reset the idle timer")
                await asyncio.wait_for(task, 3)
            finally:
                if not task.done():
                    task.cancel()
                    await asyncio.gather(task, return_exceptions=True)
        self.assertFalse(await self.has_owner())

    async def test_failed_bus_startup(self):
        with tempfile.TemporaryDirectory() as directory:
            webhook_file = Path(directory) / "webhook"
            webhook_file.write_text("http://127.0.0.1:1/unused")
            env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=(
                "unix:path=" + directory + "/missing-bus"
            ))
            for script, args in (
                ("local-notifyd.py", ["--webhook-file", str(webhook_file)]),
                ("local-notify.py", [
                    "--username", "tester", "--icon", "https://example.test/i",
                    "--title", "Test", "--content", "body",
                ]),
            ):
                result = await asyncio.to_thread(
                    subprocess.run, [sys.executable, str(ROOT / script), *args],
                    capture_output=True, text=True, timeout=5, env=env,
                )
                self.assertEqual(result.returncode, 1)
                self.assertIn("No such file", result.stderr)


if __name__ == "__main__":
    unittest.main()
