"""python-caldav adapter with scoped, conditional item writes and deletes."""

import logging
import os
from contextlib import contextmanager
from urllib.parse import unquote, urlsplit

from .config import Config, canonical_url
from .errors import PublicError


def http_status(response, *args, **kwargs):
    status = response.status_code
    codes = {
        401: ("AUTH_FAILED", "Check the host CalDAV credentials."),
        403: ("FORBIDDEN", "The CalDAV account cannot access this resource."),
        404: ("NOT_FOUND", "The CalDAV resource was not found."),
        409: ("CONFLICT", "Refresh the resource and retry."),
        412: ("CONFLICT", "Refresh the resource and retry."),
        400: ("UNSUPPORTED_DATA", "Radicale rejected the calendar data."),
        415: ("UNSUPPORTED_DATA", "Radicale rejected the component or content type."),
    }
    if status in codes:
        raise PublicError(*codes[status])
    if status >= 500 or status == 429:
        raise PublicError(
            "SERVER_UNAVAILABLE",
            "Radicale is unavailable or rate limited; retry later.",
        )
    if 300 <= status < 400:
        raise PublicError(
            "SERVER_UNAVAILABLE",
            "Redirects are disabled. Configure the canonical CalDAV endpoint.",
        )
    return response


def require_item_url(config: Config, url: str):
    target = urlsplit(url)
    collection = urlsplit(config.allowed.get("Agent", ""))
    directory, _, filename = target.path.rpartition("/")
    if (
        (target.scheme, target.netloc) != (collection.scheme, collection.netloc)
        or directory + "/" != collection.path
        or not filename.endswith(".ics")
        or any(c in unquote(filename) for c in ("/", "\\"))
        or target.query
        or target.fragment
        or target.username
        or target.password
    ):
        raise PublicError(
            "FORBIDDEN", "Item writes must stay inside the pinned Agent collection."
        )


class DavBackend:
    def __init__(self, config: Config):
        self.config = config

    @contextmanager
    def connect(self):
        # Do this before importing caldav: its debug dump can contain credentials.
        os.environ.pop("PYTHON_CALDAV_COMMDUMP", None)
        os.environ.pop("PYTHON_CALDAV_DEBUGMODE", None)
        from caldav import DAVClient
        from caldav.lib import error
        from caldav.lib.error import AuthorizationError, DAVError, NotFoundError
        from niquests.exceptions import RequestException

        error.debug_dump_communication = False
        logger = logging.getLogger("caldav")
        logger.handlers = [logging.NullHandler()]
        logger.propagate = False
        logger.setLevel(logging.CRITICAL + 1)

        config = self.config

        class ScopedClient(DAVClient):
            def request(
                self, url, method="GET", body="", headers=None, *args, **kwargs
            ):
                method = method.upper()
                if method not in {"GET", "PROPFIND", "REPORT", "OPTIONS"}:
                    if method not in {"PUT", "DELETE"} or not config.writes_enabled:
                        raise PublicError(
                            "READ_ONLY",
                            "Only explicitly enabled conditional item writes are allowed.",
                        )
                    require_item_url(config, str(url))
                    conditions = {k.lower(): v for k, v in (headers or {}).items()}
                    match = conditions.get("if-match", "")
                    create = (
                        method == "PUT"
                        and conditions.get("if-none-match") == "*"
                        and not match
                    )
                    update_or_delete = (
                        "if-none-match" not in conditions
                        and match.startswith('"')
                        and match.endswith('"')
                    )
                    if not (create or update_or_delete):
                        raise PublicError(
                            "CONFLICT",
                            "Writes require a strong ETag or create-only precondition.",
                        )
                target, origin = urlsplit(canonical_url(str(url))), urlsplit(config.url)
                if (target.scheme, target.netloc) != (origin.scheme, origin.netloc):
                    raise PublicError(
                        "FORBIDDEN", "Cross-origin CalDAV requests are not allowed."
                    )
                return super().request(url, method, body, headers, *args, **kwargs)

        try:
            with ScopedClient(
                url=config.url,
                username=config.username,
                password=config.password,
                auth_type="basic",
                timeout=config.timeout,
                ssl_verify_cert=True,
                enable_rfc6764=False,
            ) as client:
                client.session.hooks["response"].append(http_status)
                yield client
        except PublicError:
            raise
        except NotFoundError as exc:
            raise PublicError(
                "NOT_FOUND", "No item with that UID exists in this collection."
            ) from exc
        except AuthorizationError as exc:
            raise PublicError(
                "AUTH_FAILED", "Check the host CalDAV credentials and rights."
            ) from exc
        except (RequestException, DAVError, OSError) as exc:
            raise PublicError(
                "SERVER_UNAVAILABLE",
                "CalDAV operation failed. Check the host connection; reread before retrying any write.",
            ) from exc

    @staticmethod
    def new_resource(calendar, kind, uid):
        from caldav import Event, Todo

        resource_type = Event if kind == "VEVENT" else Todo
        return resource_type(
            client=calendar.client,
            parent=calendar,
            url=str(calendar.url) + uid + ".ics",
        )

    @staticmethod
    def reload(resource):
        from caldav.elements import dav

        # The data and ETag must come from the same GET, never a stale REPORT.
        resource.props.pop(dav.GetEtag.tag, None)
        return resource.load(multiget_fallback=False)

    def put(self, calendar, resource, instance, expected_etag=None):
        require_item_url(self.config, str(resource.url))
        headers = {"Content-Type": "text/calendar; charset=utf-8"}
        if expected_etag is None:
            headers["If-None-Match"] = "*"
        else:
            headers["If-Match"] = expected_etag
        response = calendar.client.put(str(resource.url), instance.to_ical(), headers)
        if response.status not in {201, 204}:
            raise PublicError(
                "SERVER_UNAVAILABLE",
                "Conditional write did not succeed; reread before retrying.",
            )
        return self.reload(resource)

    @staticmethod
    def lookup_item(calendar, kind, uid):
        from caldav.lib.error import NotFoundError

        lookup = (
            calendar.get_event_by_uid if kind == "VEVENT" else calendar.get_todo_by_uid
        )
        try:
            return lookup(uid)
        except NotFoundError as error:
            # Translate here so idempotent deletion can handle absence inside
            # the connection context, not only when that context exits.
            raise PublicError(
                "NOT_FOUND", "No item with that UID exists in Agent."
            ) from error

    def delete(self, calendar, resource, expected_etag):
        require_item_url(self.config, str(resource.url))
        # DAVClient.delete() has no headers argument in this pinned version.
        response = calendar.client.request(
            str(resource.url), "DELETE", headers={"If-Match": expected_etag}
        )
        if response.status not in {200, 204}:
            raise PublicError(
                "SERVER_UNAVAILABLE",
                "Deletion did not succeed; reread before retrying.",
            )

    @staticmethod
    def calendars(client):
        return client.get_principal().get_calendars()

    @staticmethod
    def describe(calendar):
        return {
            "url": canonical_url(str(calendar.url)),
            "name": calendar.get_display_name() or "",
            "components": sorted(calendar.get_supported_components()),
        }
