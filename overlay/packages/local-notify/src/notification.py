import json
import socket
import urllib.error
import urllib.parse
import urllib.request

BUS_NAME = "io.github.pineapplehunter.LocalNotify1"
OBJECT_PATH = "/io/github/pineapplehunter/LocalNotify1"
INTERFACE = BUS_NAME
DEFAULT_COLOR = 0x5865F2


class ValidationError(ValueError):
    pass


def format_title(title: str) -> str:
    return f"{title} [{socket.gethostname()}]"


def validate(
    username: str, icon: str, title: str, content: str, color: str
) -> None:
    if not username.strip():
        raise ValidationError("username is required")
    if len(username) > 80:
        raise ValidationError("username exceeds 80 characters")
    if not icon.strip():
        raise ValidationError("icon is required")
    parsed_icon = urllib.parse.urlparse(icon)
    if parsed_icon.scheme != "https" or not parsed_icon.netloc:
        raise ValidationError("icon must be an HTTPS URL")
    if not title.strip():
        raise ValidationError("title is required")
    if not content.strip():
        raise ValidationError("content is required")
    if len(format_title(title)) > 256:
        raise ValidationError("title with hostname exceeds 256 characters")
    if len(content) > 4096:
        raise ValidationError("content exceeds 4096 characters")
    if color:
        if len(color) != 7 or not color.startswith("#"):
            raise ValidationError("color must use the form #RRGGBB")
        try:
            int(color[1:], 16)
        except ValueError as error:
            raise ValidationError("color must use the form #RRGGBB") from error


def send_discord(
    webhook_url: str,
    username: str,
    icon: str,
    title: str,
    content: str,
    color: str,
) -> None:
    validate(username, icon, title, content, color)
    payload = {
        "username": username,
        "avatar_url": icon,
        "embeds": [
            {
                "title": format_title(title),
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
