import json
from dataclasses import replace
from uuid import uuid4

import pytest
from icalendar import Alarm
from radicale_agent.service import CalendarService
from support import WritableBackend, config


@pytest.fixture
def service():
    return CalendarService(replace(config(), writes_enabled=True), WritableBackend())


def call(service, action, **arguments):
    return service.call(
        action, json.dumps({"collection_id": "Agent", **arguments}), write=True
    )


def item(result):
    assert result["ok"], result
    return result["data"]["items"][0]


def event_args():
    return {
        "request_id": str(uuid4()),
        "title": "TEST event",
        "start": "2026-10-20T14:00:00+09:00",
        "end": "2026-10-20T15:00:00+09:00",
    }


def test_create_update_event_and_idempotency(service):
    arguments = event_args()
    event = item(call(service, "create_event", **arguments))
    assert event["start"] == arguments["start"]
    assert event["uid"] == "agent-" + arguments["request_id"]
    assert item(call(service, "create_event", **arguments))["uid"] == event["uid"]
    assert service.backend.puts == 1
    assert (
        call(service, "create_event", **(arguments | {"title": "different"}))["error"][
            "code"
        ]
        == "CONFLICT"
    )
    updated = item(
        call(
            service,
            "update_event",
            uid=event["uid"],
            expected_etag=event["etag"],
            changes={"title": "changed", "location": "Desk"},
        )
    )
    assert updated["title"] == "changed" and updated["location"] == "Desk"
    assert updated["start"] == event["start"] and updated["uid"] == event["uid"]
    assert item(call(service, "create_event", **arguments))["uid"] == event["uid"]
    assert service.backend.puts == 2
    assert (
        call(
            service,
            "update_event",
            uid=event["uid"],
            expected_etag=event["etag"],
            changes={"title": "stale"},
        )["error"]["code"]
        == "CONFLICT"
    )


def test_preserve_unrelated_fields_and_alarms(service):
    resource = service.backend.lookup("event-1")
    instance = resource.get_icalendar_instance()
    event = instance.walk("VEVENT")[0]
    event.add("X-KEEP-ME", "opaque")
    event.add("CATEGORIES", ["one", "two"])
    alarm = Alarm()
    alarm.add("ACTION", "DISPLAY")
    alarm.add("DESCRIPTION", "Reminder")
    from datetime import timedelta

    alarm.add("TRIGGER", -timedelta(minutes=10))
    event.add_component(alarm)
    service.backend.store["event-1"] = (instance.to_ical(), resource.etag)
    item(
        call(
            service,
            "update_event",
            uid="event-1",
            expected_etag=resource.etag,
            changes={"title": "changed"},
        )
    )
    stored = (
        service.backend.lookup("event-1").get_icalendar_instance().walk("VEVENT")[0]
    )
    assert str(stored["X-KEEP-ME"]) == "opaque"
    assert stored["CATEGORIES"].to_ical() == event["CATEGORIES"].to_ical()
    assert stored.walk("VALARM")[0].to_ical() == alarm.to_ical()


def test_all_day_and_duration_preservation(service):
    event = item(
        call(
            service,
            "create_event",
            **(event_args() | {"start": "2026-10-20", "end": "2026-10-22"}),
        )
    )
    assert event["all_day"] and event["end"] == "2026-10-22"
    assert not call(
        service,
        "update_event",
        uid=event["uid"],
        expected_etag=event["etag"],
        changes={"end": "2026-10-19"},
    )["ok"]
    resource = service.backend.lookup("event-1")
    instance = resource.get_icalendar_instance()
    component = instance.walk("VEVENT")[0]
    from datetime import timedelta

    component.pop("DTEND")
    component.add("DURATION", timedelta(hours=1))
    service.backend.store["event-1"] = (instance.to_ical(), resource.etag)
    updated = item(
        call(
            service,
            "update_event",
            uid="event-1",
            expected_etag=resource.etag,
            changes={"description": "changed"},
        )
    )
    stored = (
        service.backend.lookup("event-1").get_icalendar_instance().walk("VEVENT")[0]
    )
    assert "DURATION" in stored and "DTEND" not in stored
    moved = item(
        call(
            service,
            "update_event",
            uid="event-1",
            expected_etag=updated["etag"],
            changes={"start": "2026-10-20T16:00:00+09:00"},
        )
    )
    assert moved["end"] == "2026-10-20T17:00:00+09:00"


def test_task_due_priority_completion_reopen(service):
    task = item(
        call(
            service,
            "create_task",
            request_id=str(uuid4()),
            title="TEST task",
            due="2026-10-22",
            priority=3,
        )
    )
    task = item(
        call(
            service,
            "update_task",
            uid=task["uid"],
            expected_etag=task["etag"],
            changes={
                "due": "2026-10-23T12:00:00+09:00",
                "priority": 1,
                "percent_complete": 50,
            },
        )
    )
    assert (
        task["status"] == "IN-PROCESS"
        and task["priority"] == 1
        and task["percent_complete"] == 50
    )
    old_etag = task["etag"]
    done = item(call(service, "complete_task", uid=task["uid"], expected_etag=old_etag))
    assert (
        done["status"] == "COMPLETED"
        and done["percent_complete"] == 100
        and done["completed_at"]
    )
    puts = service.backend.puts
    repeated = item(
        call(service, "complete_task", uid=task["uid"], expected_etag=old_etag)
    )
    assert (
        repeated["completed_at"] == done["completed_at"]
        and service.backend.puts == puts
    )
    reopened = item(
        call(
            service,
            "update_task",
            uid=task["uid"],
            expected_etag=done["etag"],
            changes={"status": "NEEDS-ACTION", "due": None},
        )
    )
    assert (
        reopened["completed_at"] is None
        and reopened["percent_complete"] == 0
        and reopened["due"] is None
    )


def test_race_is_rejected_by_atomic_precondition(service):
    def concurrent_update(uid):
        data, _ = service.backend.store[uid]
        service.backend.store[uid] = (data, '"other-client"')

    service.backend.before_put = concurrent_update
    result = call(
        service,
        "update_event",
        uid="event-1",
        expected_etag='"seed"',
        changes={"title": "lost update"},
    )
    assert result["error"]["code"] == "CONFLICT"
    assert service.backend.puts == 0
    assert service.backend.store["event-1"][1] == '"other-client"'


@pytest.mark.parametrize(
    "property,value",
    [
        ("RRULE", {"FREQ": "DAILY"}),
        ("RDATE", None),
        ("RECURRENCE-ID", None),
        ("ATTENDEE", "mailto:test@example.test"),
    ],
)
def test_recurring_and_scheduled_items_rejected(service, property, value):
    from datetime import datetime, timezone

    resource = service.backend.lookup("event-1")
    instance = resource.get_icalendar_instance()
    instance.walk("VEVENT")[0].add(
        property,
        value if value is not None else datetime(2026, 10, 20, tzinfo=timezone.utc),
    )
    service.backend.store["event-1"] = (instance.to_ical(), resource.etag)
    assert not call(
        service,
        "update_event",
        uid="event-1",
        expected_etag=resource.etag,
        changes={"title": "must not change"},
    )["ok"]
    assert service.backend.puts == 0


@pytest.mark.parametrize(
    "action,arguments",
    [
        ("create_event", event_args() | {"start": "2026-10-20T14:00:00"}),
        ("create_event", event_args() | {"end": "2026-10-19"}),
        ("create_event", event_args() | {"title": ""}),
        ("create_event", event_args() | {"request_id": "../outside"}),
        ("create_task", {"request_id": str(uuid4()), "title": "x", "priority": 10}),
        ("create_task", {"request_id": str(uuid4()), "title": "x", "priority": True}),
        ("update_event", {"uid": "event-1", "expected_etag": '"seed"', "changes": {}}),
        (
            "update_event",
            {
                "uid": "event-1",
                "expected_etag": '"seed"',
                "changes": {"rrule": "DAILY"},
            },
        ),
        (
            "update_event",
            {"uid": "event-1", "expected_etag": 'W/"seed"', "changes": {"title": "x"}},
        ),
        (
            "update_task",
            {"uid": "task-1", "expected_etag": '"seed"', "changes": {"priority": None}},
        ),
        (
            "update_task",
            {
                "uid": "task-1",
                "expected_etag": '"seed"',
                "changes": {"status": "COMPLETED", "percent_complete": 50},
            },
        ),
        (
            "update_task",
            {
                "uid": "task-1",
                "expected_etag": '"seed"',
                "changes": {"status": "IN-PROCESS", "percent_complete": 100},
            },
        ),
        (
            "create_task",
            {"collection_id": "private", "request_id": str(uuid4()), "title": "x"},
        ),
    ],
)
def test_invalid_writes_before_network(service, action, arguments):
    assert not call(service, action, **arguments)["ok"]
    assert service.backend.connections == 0


def test_read_method_cannot_write_even_when_enabled(service):
    assert (
        service.call("create_event", json.dumps(event_args()))["error"]["code"]
        == "READ_ONLY"
    )
    service.config = replace(service.config, writes_enabled=False)
    assert call(service, "create_event", **event_args())["error"]["code"] == "READ_ONLY"
    assert service.backend.connections == 0
