"""Interactive host configuration for the Pi Remote ticket broker."""
import json
from pathlib import Path
import socket
import sys
import tempfile
from urllib.parse import urlsplit

from pi_remote_ticket import DEFAULT_ORIGIN, parse_origin


def main():
    path = Path.home() / '.config/pi-remote/host.json'
    config = json.loads(path.read_text()) if path.exists() else {}
    name = config.get('host_name') or socket.gethostname()
    name = input(f'Trusted hosts enrollment name [{name}]: ').strip() or name
    if not name.strip() or len(name.encode()) > 256:
        raise ValueError('expected a host name of at most 256 bytes')

    origin = config.get('origin', DEFAULT_ORIGIN)
    default_url = f'wss://{urlsplit(origin).netloc}/agent/ws'
    url = input(f'Agent WebSocket address [{default_url}]: ').strip() or default_url
    if not url.startswith('wss://') or not url.endswith('/agent/ws'):
        raise ValueError('expected wss://HOST[:PORT]/agent/ws')
    origin = 'https://' + url[len('wss://'):-len('/agent/ws')]
    parse_origin(origin)
    if origin.endswith('/'):
        raise ValueError('unexpected path before /agent/ws')

    config.pop('host_id', None)
    config.update(host_name=name, origin=origin)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as tmp:
        json.dump(config, tmp, indent=2)
        tmp.write('\n')
    Path(tmp.name).replace(path)
    print(f'Saved {path}: {name} → {url}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, EOFError, OSError) as exc:
        sys.exit(f'pi-remote-setup: {exc}')
