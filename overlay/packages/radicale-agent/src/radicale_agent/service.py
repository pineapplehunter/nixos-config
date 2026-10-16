"""Transport-independent authorization, query policy and normalization."""

import json
import logging
from datetime import date, datetime, timedelta

from pydantic import ValidationError

from .config import Config, canonical_url
from .dav import DavBackend
from .errors import PublicError, failure
from .models import REQUESTS, WRITE_REQUESTS, instant, parse_time
from .mutations import delete_item, mutate

MAX_REQUEST_BYTES = 64 * 1024
MAX_RESPONSE_BYTES = 2 * 1024 * 1024
AUDIT = logging.getLogger("radicale_agent.audit")


class CalendarService:
    def __init__(self, config: Config, backend=None):
        self.config = config
        self.backend = backend or DavBackend(config)

    def call(self, action: str, raw: str, *, write: bool = False) -> dict:
        alias = uid = None
        try:
            if action in WRITE_REQUESTS and (
                not write or not self.config.writes_enabled
            ):
                raise PublicError(
                    "READ_ONLY",
                    "Writes require host opt-in and the dedicated Write method.",
                )
            if write and action not in WRITE_REQUESTS:
                raise PublicError("INVALID_INPUT", "Unknown write operation.")
            if action not in REQUESTS:
                if action.startswith(("create_", "update_", "complete_", "delete_")):
                    raise PublicError(
                        "READ_ONLY", "Writes are not implemented in this release."
                    )
                raise PublicError("INVALID_INPUT", "Unknown read operation.")
            if len(raw.encode()) > MAX_REQUEST_BYTES:
                raise PublicError("INVALID_INPUT", "Request exceeds 64 KiB.")
            request = REQUESTS[action].model_validate_json(raw)
            alias = getattr(request, "collection_id", None)
            uid = getattr(request, "uid", None)
            if alias is not None and alias not in self.config.allowed:
                raise PublicError(
                    "FORBIDDEN", "Collection alias is not authorized on the host."
                )
            start = end = due_before = None
            if action == "list_events":
                start, end = parse_time(request.start), parse_time(request.end)
                if type(start) is not type(end):
                    raise PublicError(
                        "INVALID_INPUT",
                        "Start and end must both be dates or both be timestamps.",
                    )
                start, end = (
                    instant(start, self.config.timezone),
                    instant(end, self.config.timezone),
                )
                if (
                    not timedelta(0)
                    < end - start
                    <= timedelta(days=self.config.max_window_days)
                ):
                    raise PublicError(
                        "INVALID_INPUT",
                        "Event window must be positive and at most 90 days.",
                    )
            if action == "list_tasks" and request.due_before is not None:
                due_before = instant(
                    parse_time(request.due_before), self.config.timezone
                )

            with self.backend.connect() as client:
                calendars = self.backend.calendars(client)
                if action == "list_collections":
                    result = []
                    aliases = {url: key for key, url in self.config.allowed.items()}
                    for calendar in calendars:
                        key = aliases.get(canonical_url(str(calendar.url)))
                        if key is not None:
                            info = self.backend.describe(calendar)
                            self.require_agent_name(info)
                            result.append(
                                {
                                    "id": key,
                                    "name": info["name"],
                                    "supports_events": "VEVENT" in info["components"],
                                    "supports_tasks": "VTODO" in info["components"],
                                }
                            )
                    data = {
                        "items": sorted(result, key=lambda x: x["id"]),
                        "truncated": False,
                    }
                else:
                    calendar = next(
                        (
                            c
                            for c in calendars
                            if canonical_url(str(c.url)) == self.config.allowed[alias]
                        ),
                        None,
                    )
                    if calendar is None:
                        raise PublicError(
                            "NOT_FOUND",
                            "Authorized collection was not discovered. Check its host mapping and rights.",
                        )
                    kind = (
                        "VEVENT"
                        if action.endswith("event") or action == "list_events"
                        else "VTODO"
                    )
                    info = self.backend.describe(calendar)
                    self.require_agent_name(info)
                    if kind not in info["components"]:
                        raise PublicError(
                            "UNSUPPORTED_COMPONENT",
                            f"Agent does not support {kind}; ask the owner to verify the collection's supported components.",
                        )
                    deletion = None
                    if action in {"delete_event", "delete_task"}:
                        deletion = delete_item(request, calendar, kind, self.backend)
                        resources = []
                    elif action in WRITE_REQUESTS:
                        resource = mutate(action, request, calendar, kind, self.backend)
                        resources = [resource]
                        uid = str(
                            resource.get_icalendar_instance()
                            .walk(kind)[0]
                            .get("UID", "")
                        )
                    elif action == "list_events":
                        resources = calendar.search(
                            event=True, start=start, end=end, expand=True
                        )
                    elif action == "list_tasks":
                        resources = calendar.search(
                            todo=True, include_completed=request.include_completed
                        )
                    else:
                        lookup = (
                            calendar.get_event_by_uid
                            if kind == "VEVENT"
                            else calendar.get_todo_by_uid
                        )
                        resources = [self.backend.reload(lookup(request.uid))]
                    items = [deletion] if deletion is not None else []
                    seen = set()
                    limit = min(
                        getattr(request, "limit", self.config.max_results),
                        self.config.max_results,
                    )
                    for resource in resources:
                        for component in resource.get_icalendar_instance().walk(kind):
                            item = self.normalize(component, alias, resource.etag)
                            if action.startswith("get_") and item["uid"] != request.uid:
                                continue
                            if action == "list_events":
                                a = instant(
                                    parse_time(item["start"]), self.config.timezone
                                )
                                b = instant(
                                    parse_time(item["end"]), self.config.timezone
                                )
                                if not (
                                    a < end and (b > start or a == b and a >= start)
                                ):
                                    continue
                            if action == "list_tasks":
                                if not request.include_completed and (
                                    item["status"] == "COMPLETED"
                                    or item["completed_at"] is not None
                                ):
                                    continue
                                if due_before is not None and (
                                    item["due"] is None
                                    or instant(
                                        parse_time(item["due"]), self.config.timezone
                                    )
                                    >= due_before
                                ):
                                    continue
                            key = (item["uid"], item["recurrence_id"])
                            if key not in seen:
                                seen.add(key)
                                items.append(item)
                    if action.startswith("get_") and not items:
                        raise PublicError(
                            "NOT_FOUND", "No item with that exact UID was returned."
                        )
                    data = {"items": items[:limit], "truncated": len(items) > limit}
            response = {"ok": True, "data": data}
            if len(json.dumps(response).encode()) > MAX_RESPONSE_BYTES:
                raise PublicError(
                    "RESULT_TOO_LARGE",
                    "Result exceeds 2 MiB; use a smaller limit or event window.",
                )
        except ValidationError:
            response = failure(
                "INVALID_INPUT",
                "Check required fields, types, alias, UID, limit (1-200) and unexpected fields.",
            )
        except PublicError as exc:
            response = exc.response()
        except Exception:  # noqa: BLE001 - public trust boundary
            response = failure(
                "INTERNAL_ERROR",
                "Calendar operation failed; check host configuration and reread before retrying a write.",
            )
        # No titles, descriptions, credentials, URLs, raw exceptions or bodies.
        AUDIT.info(
            "action=%s collection=%s uid=%s result=%s",
            action if action in REQUESTS else "rejected",
            alias,
            json.dumps(uid),
            "OK" if response["ok"] else response["error"]["code"],
        )
        return response

    @staticmethod
    def require_agent_name(info):
        if info["name"] != "Agent":
            raise PublicError(
                "FORBIDDEN",
                "The pinned collection must be named Agent. Check its host mapping.",
            )

    def normalize(self, component, alias, etag):
        def decoded(key):
            return component.decoded(key) if key in component else None

        def timestamp(value):
            if value is None:
                return None
            if isinstance(value, datetime):
                if value.tzinfo is None:
                    value = value.replace(tzinfo=self.config.timezone)
                return value.astimezone(self.config.timezone).isoformat()
            if isinstance(value, date):
                return value.isoformat()
            raise PublicError(
                "UNSUPPORTED_DATA",
                "Calendar contains an unsupported time representation.",
            )

        result = {
            "collection_id": alias,
            "uid": str(component.get("UID", "")),
            "title": str(component.get("SUMMARY", "")),
            "description": str(component.get("DESCRIPTION", "")),
            "recurrence_id": timestamp(decoded("RECURRENCE-ID")),
            "recurring": any(
                key in component for key in ("RRULE", "RDATE", "RECURRENCE-ID")
            ),
            "etag": etag,
            "floating_time": any(
                isinstance(decoded(key), datetime) and decoded(key).tzinfo is None
                for key in ("DTSTART", "DTEND", "DUE", "RECURRENCE-ID")
            ),
        }
        if component.name == "VEVENT":
            start = decoded("DTSTART")
            if start is None:
                raise PublicError("UNSUPPORTED_DATA", "Event has no DTSTART.")
            end = decoded("DTEND")
            if end is None:
                duration = decoded("DURATION")
                end = start + (
                    duration
                    if duration is not None
                    else timedelta(days=0 if isinstance(start, datetime) else 1)
                )
            result.update(
                start=timestamp(start),
                end=timestamp(end),
                all_day=not isinstance(start, datetime),
                location=str(component.get("LOCATION", "")),
            )
        else:
            result.update(
                due=timestamp(decoded("DUE")),
                status=str(component.get("STATUS", "NEEDS-ACTION")),
                priority=int(component.get("PRIORITY", 0)),
                percent_complete=int(component.get("PERCENT-COMPLETE", 0)),
                completed_at=timestamp(decoded("COMPLETED")),
            )
        return result
