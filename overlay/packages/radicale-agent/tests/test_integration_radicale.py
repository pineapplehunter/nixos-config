"""Explicitly opted-in live tests. Only unique Agent test fixtures are mutated.

Deletion checks and the MCP roundtrip delete their own fresh fixtures. Other
checks leave fixtures for cleanup. No pre-existing items or collections/server
configuration are modified. Optional UIDs go to RADICALE_LIVE_FIXTURE_LOG.
"""

import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import httpx
import pytest
from icalendar import Alarm, Calendar, Event
from radicale_agent.config import Config
from radicale_agent.dav import DavBackend
from radicale_agent.service import CalendarService

pytestmark = pytest.mark.live


@pytest.fixture
def live():
    if os.environ.get("RADICALE_LIVE_TEST") != "1":
        pytest.skip(
            "Set RADICALE_LIVE_TEST=1 after approving the Agent test collection"
        )
    return CalendarService(Config.from_env())


@pytest.fixture
def writable(live):
    if os.environ.get("RADICALE_LIVE_WRITE_TEST") != "1":
        pytest.skip(
            "Set RADICALE_LIVE_WRITE_TEST=1 to approve creation of unique Agent test fixtures"
        )
    assert live.config.writes_enabled, "Host CALDAV_WRITES_ENABLED must be true"
    return live


def check(service, action, **arguments):
    result = service.call(
        action,
        json.dumps(arguments),
        write=action.startswith(("create_", "update_", "complete_", "delete_")),
    )
    assert result["ok"], result.get("error")
    return result["data"]


def one(service, action, **arguments):
    return check(service, action, collection_id="Agent", **arguments)["items"][0]


def record(uid, kind):
    if os.environ.get("RADICALE_LIVE_FIXTURE_LOG"):
        with Path(os.environ["RADICALE_LIVE_FIXTURE_LOG"]).open("a") as file:
            file.write(json.dumps({"uid": uid, "kind": kind}) + "\n")


def create(service, kind, **fields):
    request_id = str(uuid4())
    record("agent-" + request_id, kind)
    arguments = {
        "request_id": request_id,
        "title": "[Agent integration test] " + request_id,
        **fields,
    }
    return one(service, "create_" + kind, **arguments), arguments


def independent_client(service):
    # Independent HTTP/iCalendar path, not the service's adapter or normalizer.
    return httpx.Client(
        auth=(service.config.username, service.config.password),
        verify=True,
        follow_redirects=False,
        timeout=15,
    )


def external_get(client, service, uid):
    response = client.get(service.config.allowed["Agent"] + uid + ".ics")
    assert response.status_code == 200
    return Calendar.from_ical(response.content), response.headers["etag"]


def external_put(client, service, uid, instance, etag=None):
    headers = {
        "Content-Type": "text/calendar; charset=utf-8",
        "If-Match" if etag else "If-None-Match": etag or "*",
    }
    response = client.put(
        service.config.allowed["Agent"] + uid + ".ics",
        content=instance.to_ical(),
        headers=headers,
    )
    assert response.status_code in {201, 204}


@pytest.fixture
def temporary_item(writable):
    created = []

    def make(kind):
        fields = (
            {"start": "2026-10-20", "end": "2026-10-21"}
            if kind == "event"
            else {"due": "2026-10-20"}
        )
        item, _ = create(writable, kind, **fields)
        created.append((kind, item["uid"]))
        return item

    yield make
    # Only delete the unique items created by this fixture, even on failure.
    for kind, uid in created:
        current = writable.call(
            "get_" + kind, json.dumps({"collection_id": "Agent", "uid": uid})
        )
        if not current["ok"] and current["error"]["code"] == "NOT_FOUND":
            continue
        assert current["ok"], current.get("error")
        one(
            writable,
            "delete_" + kind,
            uid=uid,
            expected_etag=current["data"]["items"][0]["etag"],
        )


@pytest.mark.parametrize("kind", ["event", "task"])
def test_live_delete_roundtrip(writable, temporary_item, kind):
    item = temporary_item(kind)
    changed = one(
        writable,
        "update_" + kind,
        uid=item["uid"],
        expected_etag=item["etag"],
        changes={"title": item["title"] + " changed"},
    )
    stale = writable.call(
        "delete_" + kind,
        json.dumps(
            {
                "collection_id": "Agent",
                "uid": item["uid"],
                "expected_etag": item["etag"],
            }
        ),
        write=True,
    )
    assert stale["error"]["code"] == "CONFLICT"
    with independent_client(writable) as client:
        external_get(client, writable, item["uid"])
        deleted = one(
            writable, "delete_" + kind, uid=item["uid"], expected_etag=changed["etag"]
        )
        assert deleted["deleted"] and not deleted["already_absent"]
        assert (
            client.get(
                writable.config.allowed["Agent"] + item["uid"] + ".ics"
            ).status_code
            == 404
        )
    assert one(
        writable, "delete_" + kind, uid=item["uid"], expected_etag=changed["etag"]
    )["already_absent"]


def test_live_actual_if_match_delete_race(writable, temporary_item):
    event = temporary_item("event")

    class RacingBackend(DavBackend):
        def delete(self, calendar, resource, expected_etag):
            with independent_client(writable) as client:
                instance, etag = external_get(client, writable, event["uid"])
                component = instance.walk("VEVENT")[0]
                component.pop("DESCRIPTION", None)
                component.add(
                    "DESCRIPTION", "Independent change before conditional DELETE"
                )
                external_put(client, writable, event["uid"], instance, etag)
            return super().delete(calendar, resource, expected_etag)

    racing = CalendarService(writable.config, RacingBackend(writable.config))
    result = racing.call(
        "delete_event",
        json.dumps(
            {
                "collection_id": "Agent",
                "uid": event["uid"],
                "expected_etag": event["etag"],
            }
        ),
        write=True,
    )
    assert result["error"]["code"] == "CONFLICT"
    assert (
        one(writable, "get_event", uid=event["uid"])["description"]
        == "Independent change before conditional DELETE"
    )


def test_live_mcp_through_filtered_bus(writable, tmp_path):
    from test_transport import run_private_bus

    run_private_bus(tmp_path, live=True)


def test_live_discovery_and_collection_policy(live):
    items = check(live, "list_collections")["items"]
    assert len(items) == 1 and items[0]["id"] == items[0]["name"] == "Agent"
    assert items[0]["supports_events"] and items[0]["supports_tasks"]
    result = live.call(
        "get_task",
        json.dumps(
            {"collection_id": "personal", "uid": "never-contact-this-collection"}
        ),
    )
    assert not result["ok"]


def test_live_event_roundtrip_and_preservation(writable):
    event, arguments = create(
        writable,
        "event",
        start="2026-10-20T14:00:00+09:00",
        end="2026-10-20T15:00:00+09:00",
        description="Non-sensitive live fixture",
    )
    assert event["start"] == "2026-10-20T14:00:00+09:00"
    assert one(writable, "create_event", **arguments)["uid"] == event["uid"]
    assert one(writable, "get_event", uid=event["uid"])["etag"] == event["etag"]
    with independent_client(writable) as client:
        instance, etag = external_get(client, writable, event["uid"])
        component = instance.walk("VEVENT")[0]
        assert component.decoded("DTSTART") == datetime(
            2026, 10, 20, 5, tzinfo=timezone.utc
        )
        component.add("X-KEEP-ME", "external-client-property")
        component.add("CATEGORIES", ["integration-test", "preserve"])
        alarm = Alarm()
        alarm.add("ACTION", "DISPLAY")
        alarm.add("DESCRIPTION", "Fixture reminder")
        alarm.add("TRIGGER", -timedelta(minutes=10))
        component.add_component(alarm)
        external_put(client, writable, event["uid"], instance, etag)
        fresh = one(writable, "get_event", uid=event["uid"])
        updated = one(
            writable,
            "update_event",
            uid=event["uid"],
            expected_etag=fresh["etag"],
            changes={
                "title": event["title"] + " updated",
                "start": "2026-10-20T16:00:00+09:00",
                "end": "2026-10-20T17:00:00+09:00",
                "location": "Test desk",
            },
        )
        assert updated["start"] == "2026-10-20T16:00:00+09:00"
        preserved = external_get(client, writable, event["uid"])[0].walk("VEVENT")[0]
        assert str(preserved["X-KEEP-ME"]) == "external-client-property"
        assert preserved["CATEGORIES"].to_ical() == component["CATEGORIES"].to_ical()
        assert preserved.walk("VALARM")[0].to_ical() == alarm.to_ical()
        assert str(preserved["LOCATION"]) == "Test desk"
    listed = check(
        writable,
        "list_events",
        collection_id="Agent",
        start="2026-10-20",
        end="2026-10-21",
    )["items"]
    assert sum(item["uid"] == event["uid"] for item in listed) == 1
    stale = writable.call(
        "update_event",
        json.dumps(
            {
                "collection_id": "Agent",
                "uid": event["uid"],
                "expected_etag": fresh["etag"],
                "changes": {"title": "stale edit must fail"},
            }
        ),
        write=True,
    )
    assert stale["error"]["code"] == "CONFLICT"


def test_live_all_day_roundtrip(writable):
    event, _ = create(writable, "event", start="2026-10-21", end="2026-10-23")
    assert event["all_day"] and event["end"] == "2026-10-23"
    updated = one(
        writable,
        "update_event",
        uid=event["uid"],
        expected_etag=event["etag"],
        changes={"end": "2026-10-24"},
    )
    assert updated["all_day"] and updated["end"] == "2026-10-24"
    with independent_client(writable) as client:
        component = external_get(client, writable, event["uid"])[0].walk("VEVENT")[0]
        assert component.decoded("DTEND").isoformat() == "2026-10-24"
        assert component["DTEND"].params["VALUE"] == "DATE"


def test_live_task_roundtrip_completion_and_reopen(writable):
    task, arguments = create(writable, "task", due="2026-10-22", priority=3)
    assert task["priority"] == 3 and task["due"] == "2026-10-22"
    assert one(writable, "create_task", **arguments)["uid"] == task["uid"]
    task = one(
        writable,
        "update_task",
        uid=task["uid"],
        expected_etag=task["etag"],
        changes={
            "due": "2026-10-23T12:00:00+09:00",
            "priority": 1,
            "percent_complete": 50,
            "description": "Updated live fixture",
        },
    )
    assert task["percent_complete"] == 50 and task["status"] == "IN-PROCESS"
    assert task["due"] == "2026-10-23T12:00:00+09:00"
    pending = check(writable, "list_tasks", collection_id="Agent")["items"]
    assert any(item["uid"] == task["uid"] for item in pending)
    done = one(writable, "complete_task", uid=task["uid"], expected_etag=task["etag"])
    assert (
        done["status"] == "COMPLETED"
        and done["percent_complete"] == 100
        and done["completed_at"]
    )
    repeated = one(
        writable, "complete_task", uid=task["uid"], expected_etag=task["etag"]
    )
    assert (
        repeated["completed_at"] == done["completed_at"]
        and repeated["etag"] == done["etag"]
    )
    assert not any(
        item["uid"] == task["uid"]
        for item in check(writable, "list_tasks", collection_id="Agent")["items"]
    )
    assert any(
        item["uid"] == task["uid"]
        for item in check(
            writable, "list_tasks", collection_id="Agent", include_completed=True
        )["items"]
    )
    with independent_client(writable) as client:
        component = external_get(client, writable, task["uid"])[0].walk("VTODO")[0]
        assert (
            str(component["STATUS"]) == "COMPLETED"
            and int(component["PERCENT-COMPLETE"]) == 100
        )
        assert "COMPLETED" in component and int(component["PRIORITY"]) == 1
    reopened = one(
        writable,
        "update_task",
        uid=task["uid"],
        expected_etag=done["etag"],
        changes={"due": None, "status": "NEEDS-ACTION"},
    )
    assert (
        reopened["due"] is None
        and reopened["completed_at"] is None
        and reopened["percent_complete"] == 0
    )
    one(writable, "complete_task", uid=task["uid"], expected_etag=reopened["etag"])


def test_live_actual_if_match_race(writable):
    event, _ = create(
        writable,
        "event",
        start="2026-10-20T14:00:00+09:00",
        end="2026-10-20T15:00:00+09:00",
    )

    class RacingBackend(DavBackend):
        def put(self, calendar, resource, instance, expected_etag=None):
            with independent_client(writable) as client:
                other, etag = external_get(client, writable, event["uid"])
                component = other.walk("VEVENT")[0]
                component.pop("DESCRIPTION", None)
                component.add("DESCRIPTION", "Concurrent independent client change")
                external_put(client, writable, event["uid"], other, etag)
            return super().put(calendar, resource, instance, expected_etag)

    racing = CalendarService(writable.config, RacingBackend(writable.config))
    result = racing.call(
        "update_event",
        json.dumps(
            {
                "collection_id": "Agent",
                "uid": event["uid"],
                "expected_etag": event["etag"],
                "changes": {"title": "must not overwrite concurrent edit"},
            }
        ),
        write=True,
    )
    assert result["error"]["code"] == "CONFLICT"
    current = one(writable, "get_event", uid=event["uid"])
    assert (
        current["title"] == event["title"]
        and current["description"] == "Concurrent independent client change"
    )


def test_live_recurrence_expansion_and_write_rejection(writable):
    uid = "agent-live-series-" + str(uuid4())
    record(uid, "recurring-event")
    instance = Calendar()
    instance.add("VERSION", "2.0")
    instance.add("PRODID", "-//Agent integration test//EN")
    master = Event()
    master.add("UID", uid)
    master.add("SUMMARY", "[Agent integration test] recurring series")
    master.add("DTSTAMP", datetime.now(timezone.utc))
    master.add("DTSTART", datetime(2026, 10, 20, 5, tzinfo=timezone.utc))
    master.add("DTEND", datetime(2026, 10, 20, 6, tzinfo=timezone.utc))
    master.add("RRULE", {"FREQ": "DAILY", "COUNT": 3})
    instance.add_component(master)
    override = Event()
    override.add("UID", uid)
    override.add("DTSTAMP", datetime.now(timezone.utc))
    override.add("RECURRENCE-ID", datetime(2026, 10, 21, 5, tzinfo=timezone.utc))
    override.add("DTSTART", datetime(2026, 10, 21, 6, tzinfo=timezone.utc))
    override.add("DTEND", datetime(2026, 10, 21, 7, tzinfo=timezone.utc))
    override.add("SUMMARY", "[Agent integration test] moved occurrence")
    instance.add_component(override)
    with independent_client(writable) as client:
        external_put(client, writable, uid, instance)
    events = check(
        writable,
        "list_events",
        collection_id="Agent",
        start="2026-10-20",
        end="2026-10-23",
    )["items"]
    occurrences = [item for item in events if item["uid"] == uid]
    assert len(occurrences) == 3
    assert len({(item["uid"], item["recurrence_id"]) for item in occurrences}) == 3
    assert any(item["start"] == "2026-10-21T15:00:00+09:00" for item in occurrences)
    original = one(writable, "get_event", uid=uid)
    result = writable.call(
        "update_event",
        json.dumps(
            {
                "collection_id": "Agent",
                "uid": uid,
                "expected_etag": original["etag"],
                "changes": {"title": "must not change recurring series"},
            }
        ),
        write=True,
    )
    assert result["error"]["code"] in {"UNSUPPORTED_RECURRENCE", "UNSUPPORTED_DATA"}
