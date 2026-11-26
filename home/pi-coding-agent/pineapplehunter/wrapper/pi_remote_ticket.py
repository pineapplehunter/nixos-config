"""Pi Remote host ticket broker and its restricted D-Bus client."""
import asyncio
import base64
import hashlib
import http.client
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
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
DEFAULT_ORIGIN = 'https://pi-agent.s.ihavenojob.work'


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


def websocket_url(directory):
    origin = json.loads((directory / 'host.json').read_text()).get('origin', DEFAULT_ORIGIN)
    parse_origin(origin)
    return f'wss://{urlsplit(origin).netloc}/agent/ws'


class AgentKeyUnavailable(ValueError):
    """Safe local diagnostic, without key material or subprocess output."""


def agent_sign(fingerprint, message):
    if not isinstance(fingerprint, str) or not re.fullmatch(r'SHA256:[A-Za-z0-9+/]{43}', fingerprint):
        raise ValueError('invalid SSH fingerprint')
    sock = os.environ.get('SSH_AUTH_SOCK')
    if not sock:
        raise AgentKeyUnavailable('SSH_AUTH_SOCK is not set in the host broker service')
    env = {'PATH': os.environ['PATH'], 'SSH_AUTH_SOCK': sock,
           'SSH_ASKPASS_REQUIRE': 'never'}
    listing = subprocess.run(['ssh-add', '-L'], env=env, capture_output=True, timeout=5)
    if listing.returncode:
        raise AgentKeyUnavailable('host SSH agent is unavailable or has no loaded identities')
    identities = listing.stdout.splitlines()
    for identity in identities:
        fields = identity.split()
        if len(fields) < 2 or fields[0] != b'ssh-ed25519':
            continue
        pub = b' '.join(fields[:2]).decode('ascii')
        check_key(pub)
        digest = hashlib.sha256(base64.b64decode(fields[1])).digest()
        if 'SHA256:' + base64.b64encode(digest).decode().rstrip('=') != fingerprint:
            continue
        # This fresh directory contains only a public key. SSH signing must
        # be performed by the selected identity in the host's SSH agent.
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / 'selected.pub'
            path.write_text(pub + '\n')
            return subprocess.run(['ssh-keygen', '-Y', 'sign', '-n', NS, '-f', str(path)],
                                  input=message, capture_output=True, timeout=5, check=True,
                                  start_new_session=True, env=env).stdout.decode('ascii')
    raise AgentKeyUnavailable('enrolled key is not loaded in the host SSH agent')


def issue(directory, key):
    check_key(key)
    config = json.loads((directory / 'host.json').read_text())
    name = config['host_name']
    if not isinstance(name, str) or not name.strip():
        raise ValueError('missing enrolled host name')
    origin = parse_origin(config.get('origin', DEFAULT_ORIGIN))
    reply = post(origin, '/agent/challenge', {'host_name': name, 'agent_key': key})
    host = reply['host_id']
    if str(UUID(host)) != host:
        raise ValueError('expected canonical enrollment UUID')
    nonce = token(reply['challenge'], nonce=True)
    message = f'{NS}\n{host}\n{key}\n{nonce}\n'.encode()
    signature = agent_sign(reply['fingerprint'], message)
    return token(post(origin, '/agent/ticket', {'host_id': host, 'agent_key': key,
                      'challenge': nonce, 'signature': signature})['ticket'])


async def request(key=None):
    from dbus_next import Message, MessageType
    from dbus_next.aio import MessageBus

    bus = await MessageBus().connect()
    try:
        reply = await bus.call(Message(destination=BUS, path=PATH, interface=BUS,
                                       member='GetWebSocketURL' if key is None else 'RequestTicket',
                                       signature='' if key is None else 's', body=[] if key is None else [key]))
        if reply is None or reply.message_type != MessageType.METHOD_RETURN or reply.signature != 's':
            raise ValueError('ticket request rejected')
        return reply.body[0] if key is None else token(reply.body[0])
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
        def GetWebSocketURL(self) -> 's':
            try:
                return websocket_url(directory)
            except (ValueError, KeyError, TypeError, OSError):
                raise DBusError(f'{BUS}.Rejected', 'invalid gateway origin') from None

        @method()
        async def RequestTicket(self, agent_key: 's') -> 's':
            if self.active >= 8:
                raise DBusError(f'{BUS}.Busy', 'host broker busy')
            self.active += 1
            try:
                return await asyncio.to_thread(issue, directory, agent_key)
            except AgentKeyUnavailable as error:
                print(str(error), file=sys.stderr, flush=True)
                raise DBusError(f'{BUS}.KeyUnavailable', str(error)) from None
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
    if sys.argv[1:] == ['--ws-url']:
        try:
            print(asyncio.run(asyncio.wait_for(request(), timeout=5)))
        except Exception:
            sys.exit('pi-remote-request-ticket: endpoint discovery failed')
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
