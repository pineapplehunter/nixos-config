import json
from dataclasses import replace
from types import SimpleNamespace

import pytest
from caldav.lib.error import NotFoundError
from icalendar import Calendar
from radicale_agent.dav import DavBackend
from radicale_agent.errors import PublicError
from radicale_agent.service import CalendarService
from support import WritableBackend, config


@pytest.fixture
def service():
    return CalendarService(replace(config(), writes_enabled=True), WritableBackend())


def delete(service, kind="event", uid="event-1", etag='"seed"', **kwargs):
    return service.call(
        "delete_" + kind,
        json.dumps(
            {"collection_id": "Agent", "uid": uid, "expected_etag": etag, **kwargs}
        ),
        write=True,
    )


@pytest.mark.parametrize(
    "kind,uid", [("event", "event-1"), ("task", "task-1"), ("task", "task-done")]
)
def test_delete_and_repeat(service, kind, uid):
    result = delete(service, kind, uid)
    assert result == {
        "ok": True,
        "data": {
            "items": [
                {
                    "collection_id": "Agent",
                    "uid": uid,
                    "deleted": True,
                    "already_absent": False,
                }
            ],
            "truncated": False,
        },
    }
    assert uid not in service.backend.store and service.backend.deletes == 1
    assert delete(service, kind, uid)["data"]["items"][0]["already_absent"]
    assert service.backend.deletes == 1


@pytest.mark.parametrize("race", [False, True])
def test_stale_or_racing_delete_cannot_discard_an_edit(service, race):
    def edit(uid):
        data, _ = service.backend.store[uid]
        service.backend.store[uid] = (data, '"other-client"')

    if race:
        service.backend.before_delete = edit
    else:
        edit("event-1")
    assert delete(service)["error"]["code"] == "CONFLICT"
    assert service.backend.deletes == 0 and "event-1" in service.backend.store


@pytest.mark.parametrize("kind,uid", [("event", "event-1"), ("task", "task-1")])
def test_recurring_items_cannot_be_deleted(service, kind, uid):
    data, etag = service.backend.store[uid]
    instance = Calendar.from_ical(data)
    instance.subcomponents[0].add("RRULE", {"FREQ": "DAILY"})
    service.backend.store[uid] = (instance.to_ical(), etag)
    assert delete(service, kind, uid)["error"]["code"] == "UNSUPPORTED_RECURRENCE"
    assert service.backend.deletes == 0


def test_delete_requires_write_mode_and_valid_input(service):
    raw = json.dumps(
        {"collection_id": "Agent", "uid": "event-1", "expected_etag": '"seed"'}
    )
    assert service.call("delete_event", raw)["error"]["code"] == "READ_ONLY"
    assert delete(service, collection_id="private")["error"]["code"] == "INVALID_INPUT"
    assert delete(service, etag='W/"seed"')["error"]["code"] == "INVALID_INPUT"
    service.config = replace(service.config, writes_enabled=False)
    assert delete(service)["error"]["code"] == "READ_ONLY"
    assert service.backend.connections == 0


def test_uid_recreated_after_delete_is_not_silently_reported_absent(service):
    original = service.backend.delete
    data, _ = service.backend.store["event-1"]

    def recreate(calendar, resource, expected_etag):
        original(calendar, resource, expected_etag)
        service.backend.store[resource.uid] = (data, '"recreated"')

    service.backend.delete = recreate
    assert delete(service)["error"]["code"] == "CONFLICT"
    assert "event-1" in service.backend.store
    assert delete(service)["error"]["code"] == "CONFLICT"
    assert service.backend.deletes == 1


def test_library_not_found_is_translated_inside_lookup():
    def missing(_uid):
        raise NotFoundError()

    with pytest.raises(PublicError) as error:
        DavBackend.lookup_item(
            SimpleNamespace(get_event_by_uid=missing), "VEVENT", "missing"
        )
    assert error.value.code == "NOT_FOUND"
