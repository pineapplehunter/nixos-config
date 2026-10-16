"""Host-only first-connection command, deliberately not a D-Bus method."""

import json

from .config import Config
from .dav import DavBackend
from .errors import PublicError, failure


def main():
    try:
        backend = DavBackend(Config.from_env(discovery=True))
        with backend.connect() as client:
            result = {
                "ok": True,
                "data": {
                    "items": [backend.describe(c) for c in backend.calendars(client)]
                },
            }
    except PublicError as exc:
        result = exc.response()
    except Exception:  # noqa: BLE001 - never expose raw server errors
        result = failure(
            "INTERNAL_ERROR",
            "Discovery failed; check host configuration and connection.",
        )
    print(json.dumps(result))
    if not result["ok"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
