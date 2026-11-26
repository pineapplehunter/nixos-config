"""Ticket broker tests; never use configured credentials or a real gateway."""
import asyncio
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'pineapplehunter/wrapper'))
import pi_remote_ticket as broker


class TicketTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for name in ('host_ed25519', 'agent'):
            subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', '',
                            '-f', self.root / name], check=True)
        self.key = (self.root / 'agent.pub').read_text().strip()
        self.host = '12345678-1234-4abc-abcd-123456789abc'
        self.config = {'origin': 'https://private.example:5151', 'host_name': 'build-laptop'}
        (self.root / 'host.json').write_text(json.dumps(self.config))
        self.nonce = base64.urlsafe_b64encode(bytes(range(32))).decode().rstrip('=')

    def test_endpoint_from_host_origin(self):
        self.assertEqual(broker.websocket_url(self.root), 'wss://private.example:5151/agent/ws')

    def test_name_only_configuration(self):
        (self.root / 'host.json').write_text(json.dumps({'host_name': 'build-laptop'}))
        self.assertEqual(broker.websocket_url(self.root), 'wss://pi-agent.s.ihavenojob.work/agent/ws')

    def test_signed_exchange(self):
        sock = self.root / 'ssh-agent.sock'
        env = self.enterContext(patch.dict(os.environ, {'SSH_AUTH_SOCK': str(sock)}))
        agent = subprocess.Popen(['ssh-agent', '-D', '-a', str(sock)], stdout=subprocess.DEVNULL)
        self.addCleanup(agent.wait, 5)
        self.addCleanup(agent.terminate)
        for _ in range(100):
            if sock.is_socket():
                break
            time.sleep(.01)
        for name in ('agent', 'host_ed25519'):
            subprocess.run(['ssh-add', str(self.root / name)], env=env, check=True, stderr=subprocess.DEVNULL)
            (self.root / name).unlink()
        fingerprint = subprocess.check_output(['ssh-keygen', '-lf', self.root / 'host_ed25519.pub']).split()[1].decode()
        with self.assertRaisesRegex(ValueError, 'not loaded'):
            broker.agent_sign('SHA256:' + 'A' * 43, b'no matching identity')
        result = base64.urlsafe_b64encode(b'synthetic ticket').decode().rstrip('=')
        def gateway(origin, path, body):
            self.assertEqual(origin, ('private.example', 5151))
            binding = {'host_id': self.host, 'agent_key': self.key}
            if path == '/agent/challenge':
                self.assertEqual(body, {'host_name': 'build-laptop', 'agent_key': self.key})
                return {'challenge': self.nonce, 'host_id': self.host, 'fingerprint': fingerprint}
            self.assertEqual(path, '/agent/ticket')
            (self.root / 'sig').write_text(body.pop('signature'))
            self.assertEqual(body, {**binding, 'challenge': self.nonce})
            (self.root / 'signers').write_text('host ' + (self.root / 'host_ed25519.pub').read_text())
            subprocess.run(['ssh-keygen', '-Y', 'verify', '-I', 'host', '-f', self.root / 'signers',
                            '-n', 'pi-remote-host-v1', '-s', self.root / 'sig'], check=True,
                           input=f'pi-remote-host-v1\n{self.host}\n{self.key}\n{self.nonce}\n'.encode(),
                           stdout=subprocess.DEVNULL)
            return {'ticket': result}
        with patch.object(broker, 'post', side_effect=gateway) as post:
            self.assertEqual(broker.issue(self.root, self.key), result)
            self.assertEqual(post.call_count, 2)

    def test_rejects_noncanonical_keys_before_any_network(self):
        for key in (self.key + ' x', self.key.replace(' ', '  '), self.key + '\n',
                    self.key.replace('AAAA', 'BBBB', 1), 'ssh-ed25519 YQ==', 'a' * 999):
            with self.subTest(key=key), patch.object(broker, 'post') as post, self.assertRaises(ValueError):
                broker.issue(self.root, key)
            post.assert_not_called()

    def test_rejects_invalid_challenge_before_signing(self):
        for nonce in ('?', 'AA', self.nonce + '=', self.nonce + '\n'):
            with patch.object(broker, 'post', return_value={'challenge': nonce, 'host_id': self.host}) as post, self.assertRaises(ValueError):
                broker.issue(self.root, self.key)
            self.assertEqual(post.call_count, 1)

    def test_origin_and_redirects(self):
        for url in ('http://plain', 'https://user@host', 'https://host/test', 'https://host?url=x',
                    'https://a\\@x', 'https://host#other'):
            with self.assertRaises(ValueError):
                broker.parse_origin(url)
        with patch.object(broker.http.client, 'HTTPSConnection') as connection:
            connection.return_value.getresponse.return_value.status = 307
            with self.assertRaises(ValueError):
                broker.post(('example.test', 443), '/agent/ticket', {})
            self.assertEqual(connection.return_value.request.call_count, 1)


@unittest.skipUnless(os.environ.get('PI_WRAPPER_TEST_PRIVATE_BUS') == '1',
                     'requires a private dbus-run-session')
class PrivateBusTest(unittest.IsolatedAsyncioTestCase):
    async def test_cli_roundtrip(self):
        from dbus_next import Message
        from dbus_next.aio import MessageBus

        key = 'ssh-ed25519 ' + base64.b64encode(b'\0\0\0\x0bssh-ed25519\0\0\0\x20' + b'x' * 32).decode()
        ticket = base64.urlsafe_b64encode(b'fake ticket').decode().rstrip('=')
        bus = await MessageBus().connect()
        # Never load a configured key or contact the network.
        with patch.object(broker, 'issue', return_value=ticket) as issue:
            task = asyncio.create_task(broker.serve())
            try:
                async with asyncio.timeout(5):
                    while not (await bus.call(Message(destination='org.freedesktop.DBus',
                               interface='org.freedesktop.DBus', path='/org/freedesktop/DBus',
                               member='NameHasOwner', signature='s', body=[broker.BUS]))).body[0]:
                        await asyncio.sleep(0.01)
                    proc = await asyncio.create_subprocess_exec(sys.executable, broker.__file__,
                            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE)
                    stdout, _ = await proc.communicate((key + '\n').encode())
                    self.assertEqual(proc.returncode, 0)
                    self.assertEqual(stdout, (ticket + '\n').encode())
                    self.assertEqual(issue.call_args.args[1], key)
                    with patch.object(broker, 'websocket_url', return_value='wss://test.local/agent/ws'):
                        proc = await asyncio.create_subprocess_exec(sys.executable, broker.__file__, '--ws-url',
                                stdout=asyncio.subprocess.PIPE)
                        stdout, _ = await proc.communicate()
                        self.assertEqual(proc.returncode, 0)
                        self.assertEqual(stdout, b'wss://test.local/agent/ws\n')
            finally:
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)
                bus.disconnect()


if __name__ == '__main__':
    unittest.main()
