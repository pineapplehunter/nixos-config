"""Non-recurring item mutations; no collection-management API."""

import hashlib
import json
from datetime import datetime, timezone

from icalendar import Calendar, Event, Todo

from .errors import PublicError
from .models import event_times, parse_time

REQUEST_HASH = "X-RADICALE-AGENT-REQUEST-HASH"


def component_for_write(instance, kind, uid):
    components = [c for c in instance.subcomponents if c.name != "VTIMEZONE"]
    if (
        len(components) != 1
        or components[0].name != kind
        or str(components[0].get("UID", "")) != uid
    ):
        raise PublicError(
            "UNSUPPORTED_DATA", "Only a single matching event or task can be modified."
        )
    component = components[0]
    if any(key in component for key in ("RRULE", "RDATE", "EXDATE", "RECURRENCE-ID")):
        raise PublicError(
            "UNSUPPORTED_RECURRENCE", "Recurring items and overrides are read-only."
        )
    if "METHOD" in instance or "ORGANIZER" in component or "ATTENDEE" in component:
        raise PublicError(
            "UNSUPPORTED_DATA", "Invitations and scheduled items are read-only."
        )
    return component


def ical_time(value):
    # Offset-only RFC 3339 inputs do not name a real TZID. Store instants in
    # UTC instead of emitting an unresolved TZID such as "UTC+09:00".
    return value.astimezone(timezone.utc) if isinstance(value, datetime) else value


def replace(component, key, value):
    component.pop(key, None)
    if value is not None:
        component.add(key, value)


def completion(component, changes, now):
    if "status" not in changes and "percent_complete" not in changes:
        return
    status = changes.get("status")
    percent = changes.get("percent_complete")
    if status is None:
        status = (
            "COMPLETED"
            if percent == 100
            else "NEEDS-ACTION"
            if percent == 0
            else "IN-PROCESS"
        )
    if status == "COMPLETED":
        percent = 100
        if "COMPLETED" not in component:
            replace(component, "COMPLETED", now)
    else:
        if percent is None:
            percent = (
                int(component.get("PERCENT-COMPLETE", 0))
                if status == "IN-PROCESS"
                else 0
            )
            if percent == 100:
                percent = 0
        component.pop("COMPLETED", None)
    replace(component, "STATUS", status)
    replace(component, "PERCENT-COMPLETE", percent)


def delete_item(request, calendar, kind, backend):
    result = {
        "collection_id": request.collection_id,
        "uid": request.uid,
        "deleted": True,
        "already_absent": False,
    }
    try:
        resource = backend.lookup_item(calendar, kind, request.uid)
    except PublicError as error:
        if error.code != "NOT_FOUND":
            raise
        return result | {"already_absent": True}
    resource = backend.reload(resource)
    component_for_write(resource.get_icalendar_instance(), kind, request.uid)
    if not resource.etag or resource.etag != request.expected_etag:
        raise PublicError(
            "CONFLICT",
            "This item changed or has no usable ETag. Refresh before deleting.",
        )
    try:
        backend.delete(calendar, resource, request.expected_etag)
    except PublicError as error:
        if error.code != "NOT_FOUND":
            raise
    # Verify by UID, not the old resource URL: clients can rename resources.
    try:
        backend.lookup_item(calendar, kind, request.uid)
    except PublicError as error:
        if error.code == "NOT_FOUND":
            return result
        raise
    raise PublicError(
        "CONFLICT", "The UID is still present after deletion. Refresh before retrying."
    )


def mutate(action, request, calendar, kind, backend):
    now = datetime.now(timezone.utc)
    if action.startswith("create_"):
        # Stable resource URL and UID make retries safe, even after a lost reply.
        uid = "agent-" + request.request_id
        fingerprint = hashlib.sha256(
            json.dumps(request.model_dump(), sort_keys=True).encode()
        ).hexdigest()
        resource = backend.new_resource(calendar, kind, uid)
        try:
            backend.reload(resource)
        except PublicError as error:
            if error.code != "NOT_FOUND":
                raise
        else:
            component = component_for_write(
                resource.get_icalendar_instance(), kind, uid
            )
            if str(component.get(REQUEST_HASH, "")) != fingerprint:
                raise PublicError(
                    "CONFLICT",
                    "This request_id is already in use with different creation inputs.",
                )
            return resource
        instance = Calendar()
        instance.add("PRODID", "-//radicale-agent//EN")
        instance.add("VERSION", "2.0")
        component = Event() if kind == "VEVENT" else Todo()
        component.add("UID", uid)
        component.add("DTSTAMP", now)
        component.add("CREATED", now)
        component.add("SUMMARY", request.title)
        component.add("DESCRIPTION", request.description)
        component.add(REQUEST_HASH, fingerprint)
        if kind == "VEVENT":
            start, end = event_times(request.start, request.end)
            component.add("DTSTART", ical_time(start))
            component.add("DTEND", ical_time(end))
            component.add("LOCATION", request.location)
        else:
            if request.due is not None:
                component.add("DUE", ical_time(parse_time(request.due)))
            component.add("PRIORITY", request.priority)
            component.add("STATUS", "NEEDS-ACTION")
            component.add("PERCENT-COMPLETE", 0)
        instance.add_component(component)
        return backend.put(calendar, resource, instance)

    lookup = calendar.get_event_by_uid if kind == "VEVENT" else calendar.get_todo_by_uid
    resource = backend.reload(lookup(request.uid))
    instance = resource.get_icalendar_instance()
    component = component_for_write(instance, kind, request.uid)
    if (
        action == "complete_task"
        and str(component.get("STATUS", "")) == "COMPLETED"
        and int(component.get("PERCENT-COMPLETE", 0)) == 100
        and "COMPLETED" in component
    ):
        return resource  # Already complete: no write, safe even with the previous ETag.
    if not resource.etag or resource.etag != request.expected_etag:
        raise PublicError(
            "CONFLICT", "This item changed or has no usable ETag. Refresh and retry."
        )
    changes = (
        {"status": "COMPLETED"}
        if action == "complete_task"
        else request.changes.model_dump(exclude_unset=True)
    )
    names = {
        "title": "SUMMARY",
        "description": "DESCRIPTION",
        "location": "LOCATION",
        "priority": "PRIORITY",
        "due": "DUE",
        "start": "DTSTART",
        "end": "DTEND",
    }
    for key, value in changes.items():
        if key in names:
            replace(
                component,
                names[key],
                ical_time(parse_time(value))
                if key in {"due", "start", "end"} and value is not None
                else value,
            )
    if kind == "VEVENT":
        if "start" in changes or "end" in changes:
            if "DTEND" not in component and "DURATION" in component:
                replace(
                    component,
                    "DTEND",
                    component.decoded("DTSTART") + component.decoded("DURATION"),
                )
            component.pop("DURATION", None)
            start = component.decoded("DTSTART")
            if "DTEND" not in component:
                raise PublicError(
                    "INVALID_INPUT", "Supply an end when changing this event's start."
                )
            event_times(start.isoformat(), component.decoded("DTEND").isoformat())
    else:
        if changes.get("due") is not None:
            component.pop("DURATION", None)
        completion(component, changes, now)
        # A due date cannot invalidate an existing task DTSTART.
        if "DUE" in component and "DTSTART" in component:
            start, due = component.decoded("DTSTART"), component.decoded("DUE")
            if type(start) is not type(due) or due < start:
                raise PublicError(
                    "INVALID_INPUT",
                    "Task due must match DTSTART's type and not precede it.",
                )
    replace(component, "LAST-MODIFIED", now)
    replace(component, "DTSTAMP", now)
    replace(component, "SEQUENCE", int(component.get("SEQUENCE", 0)) + 1)
    return backend.put(calendar, resource, instance, request.expected_etag)
