import json
import urllib.error
import urllib.request

BUS_NAME = "io.github.pineapplehunter.LocalNotify1"
OBJECT_PATH = "/io/github/pineapplehunter/LocalNotify1"
INTERFACE = BUS_NAME
DEFAULT_COLOR = 0x5865F2


class ValidationError(ValueError):
    pass


def validate(title: str, content: str, color: str) -> None:
    if not title.strip():
        raise ValidationError("title is required")
    if not content.strip():
        raise ValidationError("content is required")
    if len(title.encode()) > 256:
        raise ValidationError("title exceeds 256 bytes")
    if len(content.encode()) > 4096:
        raise ValidationError("content exceeds 4096 bytes")
    if color:
        if len(color) != 7 or not color.startswith("#"):
            raise ValidationError("color must use the form #RRGGBB")
        try:
            int(color[1:], 16)
        except ValueError as error:
            raise ValidationError("color must use the form #RRGGBB") from error


def send_discord(webhook_url: str, title: str, content: str, color: str) -> None:
    validate(title, content, color)
    payload = {
        "username": "Local Notifier",
        "embeds": [
            {
                "title": title,
                "description": content,
                "color": int(color[1:], 16) if color else DEFAULT_COLOR,
            }
        ],
        "allowed_mentions": {"parse": []},
    }
    request = urllib.request.Request(
        webhook_url,
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            "User-Agent": "local-notify/1.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            if not 200 <= response.status < 300:
                raise RuntimeError(f"Discord webhook returned HTTP {response.status}")
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"Discord webhook returned HTTP {error.code}") from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"sending Discord request: {error.reason}") from error
