"""Host-only configuration. No credential file is read by the MCP facade."""

import json
import os
import stat
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit
from zoneinfo import ZoneInfo

from .errors import PublicError


def canonical_url(value: str) -> str:
    parts = urlsplit(value)
    if (
        not parts.hostname
        or parts.username is not None
        or parts.password is not None
        or parts.query
        or parts.fragment
        or parts.scheme not in {"https", "http"}
        or (
            parts.scheme == "http"
            and parts.hostname not in {"127.0.0.1", "::1", "localhost"}
        )
    ):
        raise ValueError(
            "HTTPS required except on loopback; no URL credentials/query/fragment"
        )
    # Compare origins and collection paths, never display names.
    port = parts.port
    host = parts.hostname.lower()
    if ":" in host:
        host = f"[{host}]"
    if port is not None and port != {"https": 443, "http": 80}[parts.scheme]:
        host += f":{port}"
    return urlunsplit((parts.scheme, host, parts.path.rstrip("/") + "/", "", ""))


@dataclass(frozen=True)
class Config:
    url: str
    username: str = field(repr=False)
    password: str = field(repr=False)
    allowed: dict[str, str]
    timezone: ZoneInfo = field(default_factory=lambda: ZoneInfo("UTC"))
    max_window_days: int = 90
    max_results: int = 200
    timeout: int = 10
    writes_enabled: bool = False

    @classmethod
    def from_env(cls, *, discovery: bool = False) -> "Config":
        try:
            url = canonical_url(os.environ["CALDAV_URL"])
            credentials_path = Path(os.environ["CALDAV_CREDENTIALS_FILE"])
            info = credentials_path.stat()
            if (
                not credentials_path.is_absolute()
                or not stat.S_ISREG(info.st_mode)
                or info.st_mode & 0o077
                or info.st_size > 16384
            ):
                raise ValueError
            credentials = json.loads(credentials_path.read_text())
            username, password = credentials["username"], credentials["password"]
            if (
                not isinstance(username, str)
                or not isinstance(password, str)
                or not username
                or not password
            ):
                raise ValueError
            target = os.environ.get("CALDAV_AGENT_COLLECTION_URL")
            allowed = {"Agent": canonical_url(target)} if target else {}
            if not allowed and not discovery:
                raise ValueError
            if target and urlsplit(allowed["Agent"])[:2] != urlsplit(url)[:2]:
                raise ValueError
            write_mode = os.environ.get("CALDAV_WRITES_ENABLED", "false")
            if write_mode not in {"true", "false"}:
                raise ValueError
            return cls(
                url,
                username,
                password,
                allowed,
                ZoneInfo(os.environ.get("APP_TIMEZONE", "UTC")),
                writes_enabled=write_mode == "true",
            )
        except (KeyError, TypeError, ValueError, OSError) as exc:
            raise PublicError(
                "CONFIG_ERROR",
                "Check the private JSON credentials file (CALDAV_CREDENTIALS_FILE, mode 0600/0400), timezone and Agent URL.",
            ) from exc
