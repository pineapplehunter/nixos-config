"""Pi Remote host ticket broker and its restricted D-Bus client."""
import asyncio
import base64
import http.client
import json
import os
from pathlib import Path
import re
import ssl
import subprocess
import sys
from urllib.parse import urlsplit
from uuid import UUID

BUS = "io.github.pineapplehunter.PiRemoteTicket1"
PATH = "/io/github/pineapplehunter/PiRemoteTicket1"
NS = "pi-remote-host-v1"
MAX_KEY = 80


def check_key(key):
    if len(key) > MAX_KEY or not key.startswith("ssh-ed25519 "):
        raise ValueError("expected canonical ed25519 key")
    encoded = key[12:]
    raw = base64.b64decode(encoded, validate=True)
    if (len(raw) != 51 or not raw.startswith(b"\0\0\0\x0bssh-ed25519\0\0\0\x20")
            or base64.b64encode(raw).decode() != encoded):
        raise ValueError("invalid ed25519 public key")


def token(value, *, nonce=False):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,1024}", value):
        raise ValueError("invalid token")
    raw = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    if base64.urlsafe_b64encode(raw).decode().rstrip("=") != value or (nonce and len(raw) != 32):
        raise ValueError("invalid token encoding")
    return value


def parse_origin(url):
    parts = urlsplit(url)
    if (not url.isascii() or any(ord(c) < 33 or ord(c) == 127 for c in url)
            or parts.scheme != 'https' or not parts.hostname or parts.username is not None
            or parts.path not in ('', '/') or any(c in url for c in ('?', '#', '\\'))):
        raise ValueError('expected a bare HTTPS origin')
    return parts.hostname, parts.port


def post(origin, path, payload):
    # HTTPSConnection neither follows redirects nor honors proxy URLs.
    conn = http.client.HTTPSConnection(*origin, timeout=5, context=ssl.create_default_context())
    try:
        conn.request('POST', path, json.dumps(payload).encode(), {'Content-Type': 'application/json'})
        response = conn.getresponse()
        if not 200 <= response.status < 300:
            raise ValueError('gateway rejected request')
        data = response.read(4097)
        if len(data) > 4096:
            raise ValueError('gateway response too large')
        return json.loads(data)
    finally:
        conn.close()


def issue(directory, key):
    check_key(key)
    config = json.loads((directory / 'host.json').read_text())
    host = config['host_id']
    if str(UUID(host)) != host:
        raise ValueError('expected canonical host UUID')
    origin = parse_origin(config['origin'])
    binding = {'host_id': host, 'agent_key': key}
    nonce = token(post(origin, '/agent/challenge', binding)['challenge'], nonce=True)
    message = f'{NS}\n{host}\n{key}\n{nonce}\n'.encode()
    signed = subprocess.run(['ssh-keygen', '-Y', 'sign', '-n', NS, '-f', str(directory / 'host_ed25519')],
                            input=message, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            timeout=5, check=True, start_new_session=True,
                            env={'PATH': os.environ['PATH'], 'SSH_ASKPASS_REQUIRE': 'never'})
    return token(post(origin, '/agent/ticket', {**binding, 'challenge': nonce,
                      'signature': signed.stdout.decode('ascii')})['ticket'])


async def request(key):
    from dbus_next import Message, MessageType
    from dbus_next.aio import MessageBus

    bus = await MessageBus().connect()
    try:
        reply = await bus.call(Message(destination=BUS, path=PATH, interface=BUS,
                                       member='RequestTicket', signature='s', body=[key]))
        if reply is None or reply.message_type != MessageType.METHOD_RETURN or reply.signature != 's':
            raise ValueError('ticket request rejected')
        return token(reply.body[0])
    finally:
        bus.disconnect()


async def serve():
    from dbus_next import DBusError, NameFlag, RequestNameReply
    from dbus_next.aio import MessageBus
    from dbus_next.service import ServiceInterface, method

    directory = Path.home() / '.config/pi-remote'

    class Broker(ServiceInterface):
        active = 0

        @method()
        async def RequestTicket(self, agent_key: 's') -> 's':
            if self.active >= 8:
                raise DBusError(f'{BUS}.Busy', 'host broker busy')
            self.active += 1
            try:
                return await asyncio.to_thread(issue, directory, agent_key)
            except Exception:
                # Never echo credentials, remote response bodies or paths over D-Bus.
                raise DBusError(f'{BUS}.Rejected', 'ticket request failed') from None
            finally:
                self.active -= 1

    bus = await MessageBus().connect()
    bus.export(PATH, Broker(BUS))
    if await bus.request_name(BUS, NameFlag.DO_NOT_QUEUE) != RequestNameReply.PRIMARY_OWNER:
        raise RuntimeError('broker name unavailable')
    await bus.wait_for_disconnect()


def main():
    if sys.argv[1:] == ['--dbus']:
        asyncio.run(serve())
        return
    if sys.argv[1:]:
        sys.exit('usage: pi-remote-request-ticket < agent.pub')
    try:
        data = sys.stdin.buffer.read(MAX_KEY + 2)
        key = data.removesuffix(b'\n').decode('ascii')
        check_key(key)
        print(asyncio.run(asyncio.wait_for(request(key), timeout=18)))
    except Exception:
        sys.exit('pi-remote-request-ticket: ticket request failed')


if __name__ == '__main__':
    main()
