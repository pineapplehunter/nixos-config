import json
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest
from radicale_agent.config import Config, canonical_url
from radicale_agent.dav import http_status
from radicale_agent.errors import PublicError
from radicale_agent.models import parse_time
from radicale_agent.service import CalendarService
from support import Backend, Resource, config


@pytest.fixture
def service():
    return CalendarService(config(), Backend())


def call(service, action, **kwargs):
    return service.call(action, json.dumps(kwargs))


def test_discovery_is_url_pinned(service):
    result = call(service, "list_collections")
    assert result == {
        "ok": True,
        "data": {
            "items": [
                {
                    "id": "Agent",
                    "name": "Agent",
                    "supports_events": True,
                    "supports_tasks": True,
                }
            ],
            "truncated": False,
        },
    }
    # Same name, different URL must not grant access.
    service.backend.collection.url = "https://dav.example.test/user/impostor/"
    assert call(service, "list_collections")["data"]["items"] == []
    assert (
        call(service, "get_event", collection_id="Agent", uid="event-1")["error"][
            "code"
        ]
        == "NOT_FOUND"
    )


def test_name_must_be_agent(service):
    service.backend.collection.get_display_name = lambda: "Personal"
    assert call(service, "list_collections")["error"]["code"] == "FORBIDDEN"


@pytest.mark.parametrize(
    "action,params",
    [
        ("get_event", {"collection_id": "private", "uid": "event-1"}),
        ("get_event", {"collection_id": "https://evil.test/", "uid": "event-1"}),
        ("get_event", {"collection_id": "Agent", "uid": "x\n"}),
        (
            "list_events",
            {
                "collection_id": "Agent",
                "start": "2026-10-20T10:00:00",
                "end": "2026-10-21T10:00:00",
            },
        ),
        (
            "list_events",
            {"collection_id": "Agent", "start": "2026-01-01", "end": "2026-12-31"},
        ),
        (
            "list_events",
            {"collection_id": "Agent", "start": "2026-10-21", "end": "2026-10-20"},
        ),
        (
            "list_events",
            {
                "collection_id": "Agent",
                "start": "2026-10-20",
                "end": "2026-10-21T10:00:00Z",
            },
        ),
        ("list_tasks", {"collection_id": "Agent", "limit": 201}),
        ("list_tasks", {"collection_id": "Agent", "limit": True}),
        ("list_tasks", {"collection_id": "Agent", "include_completed": "false"}),
        ("list_tasks", {"collection_id": "Agent", "extra": 1}),
        ("list_tasks", {"collection_id": "Agent", "due_before": "invalid"}),
        ("list_collections", {"url": "https://evil.test"}),
    ],
)
def test_reject_before_network(service, action, params):
    assert not call(service, action, **params)["ok"]
    assert service.backend.connections == 0


@pytest.mark.parametrize(
    "action",
    [
        "create_event",
        "update_event",
        "create_task",
        "update_task",
        "complete_task",
        "delete_event",
    ],
)
def test_no_writes(service, action):
    assert call(service, action)["error"]["code"] == "READ_ONLY"
    assert service.backend.connections == 0


def test_json_limits(service):
    assert not service.call("list_collections", "not json")["ok"]
    assert not service.call("list_collections", " " * 65537)["ok"]
    assert not service.call("arbitrary_http", "{}")["ok"]
    assert service.backend.connections == 0


def test_events_timezone_and_exclusive_dates(service):
    result = call(
        service,
        "list_events",
        collection_id="Agent",
        start="2026-10-20",
        end="2026-10-24",
    )
    assert result["ok"]
    event, all_day = result["data"]["items"]
    assert event["start"] == "2026-10-20T14:00:00+09:00"
    assert event["etag"] == '"test-etag"'
    assert all_day["all_day"] and all_day["end"] == "2026-10-23"
    query = service.backend.collection.query
    assert query["expand"] and query["event"]
    assert query["start"] == datetime(2026, 10, 19, 15, tzinfo=timezone.utc)
    assert not call(
        service,
        "list_events",
        collection_id="Agent",
        start="2026-10-23",
        end="2026-10-24",
    )["data"]["items"]


def test_tasks_priority_due_completion_and_limit(service):
    pending = call(service, "list_tasks", collection_id="Agent")["data"]["items"]
    assert len(pending) == 1
    assert pending[0]["due"] == "2026-10-22" and pending[0]["priority"] == 3
    all_tasks = call(
        service, "list_tasks", collection_id="Agent", include_completed=True, limit=1
    )["data"]
    assert all_tasks["truncated"] and len(all_tasks["items"]) == 1
    done = call(service, "get_task", collection_id="Agent", uid="task-done")["data"][
        "items"
    ][0]
    assert (
        done["percent_complete"] == 100
        and done["completed_at"] == "2026-10-20T14:00:00+09:00"
    )
    assert not call(
        service, "list_tasks", collection_id="Agent", due_before="2026-10-22"
    )["data"]["items"]


def test_exact_uid_and_component_support(service):
    assert (
        len(
            call(service, "get_event", collection_id="Agent", uid="event-1")["data"][
                "items"
            ]
        )
        == 1
    )
    assert (
        call(service, "get_event", collection_id="Agent", uid="event")["error"]["code"]
        == "NOT_FOUND"
    )
    service.backend.collection.components = ["VTODO"]
    assert (
        call(service, "get_event", collection_id="Agent", uid="event-1")["error"][
            "code"
        ]
        == "UNSUPPORTED_COMPONENT"
    )


def test_recurrence_ids_and_duplicates(service):
    text = """BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:series
RECURRENCE-ID:20261020T050000Z
DTSTART:20261020T060000Z
DTEND:20261020T070000Z
END:VEVENT
BEGIN:VEVENT
UID:series
RECURRENCE-ID:20261021T050000Z
DTSTART:20261021T050000Z
DTEND:20261021T060000Z
END:VEVENT
END:VCALENDAR
"""
    service.backend.collection.search = lambda **kw: [Resource(text), Resource(text)]
    items = call(
        service,
        "list_events",
        collection_id="Agent",
        start="2026-10-20",
        end="2026-10-23",
    )["data"]["items"]
    assert len(items) == 2
    assert items[0]["recurrence_id"] != items[1]["recurrence_id"]
    assert all(i["recurring"] for i in items)


def test_errors_sanitized(service, caplog):
    def broken(**kw):
        raise RuntimeError("private-password Authorization: secret")

    service.backend.collection.search = broken
    with caplog.at_level("INFO"):
        result = call(service, "list_tasks", collection_id="Agent")
    assert result["error"]["code"] == "INTERNAL_ERROR"
    assert "private-password" not in json.dumps(result) + caplog.text
    assert "Authorization" not in caplog.text


@pytest.mark.parametrize(
    "status,code",
    [
        (401, "AUTH_FAILED"),
        (403, "FORBIDDEN"),
        (404, "NOT_FOUND"),
        (409, "CONFLICT"),
        (412, "CONFLICT"),
        (503, "SERVER_UNAVAILABLE"),
        (302, "SERVER_UNAVAILABLE"),
    ],
)
def test_status_mapping(status, code):
    with pytest.raises(PublicError) as err:
        http_status(SimpleNamespace(status_code=status))
    assert err.value.code == code


@pytest.mark.parametrize(
    "url",
    [
        "http://remote.test/",
        "https://user:secret@dav.test/",
        "https://dav.test/?secret=x",
        "https://dav.test/#x",
    ],
)
def test_unsafe_urls(url):
    with pytest.raises(ValueError):
        canonical_url(url)


def test_host_configuration(monkeypatch, tmp_path):
    credentials = tmp_path / "credentials.json"
    credentials.write_text(
        json.dumps({"username": "private-user", "password": "private-password"})
    )
    credentials.chmod(0o600)
    monkeypatch.setenv("CALDAV_URL", "https://dav.example.test/")
    monkeypatch.setenv("CALDAV_CREDENTIALS_FILE", str(credentials))
    monkeypatch.delenv("CALDAV_AGENT_COLLECTION_URL", raising=False)
    with pytest.raises(PublicError):
        Config.from_env()
    assert Config.from_env(discovery=True).allowed == {}
    monkeypatch.setenv(
        "CALDAV_AGENT_COLLECTION_URL", "https://dav.example.test/user/test/"
    )
    assert set(Config.from_env().allowed) == {"Agent"}
    assert "private-password" not in repr(Config.from_env())
    assert not Config.from_env().writes_enabled
    monkeypatch.setenv("CALDAV_WRITES_ENABLED", "true")
    assert Config.from_env().writes_enabled
    monkeypatch.setenv("CALDAV_WRITES_ENABLED", "invalid")
    with pytest.raises(PublicError):
        Config.from_env()
    monkeypatch.delenv("CALDAV_WRITES_ENABLED")
    monkeypatch.setenv("CALDAV_AGENT_COLLECTION_URL", "https://evil.test/Agent/")
    with pytest.raises(PublicError):
        Config.from_env()


def test_credentials_are_file_only(monkeypatch, tmp_path):
    monkeypatch.setenv("CALDAV_URL", "https://dav.example.test/")
    monkeypatch.setenv("CALDAV_USERNAME", "ignored-user")
    monkeypatch.setenv("CALDAV_PASSWORD", "ignored-password")
    monkeypatch.delenv("CALDAV_CREDENTIALS_FILE", raising=False)
    with pytest.raises(PublicError):
        Config.from_env(discovery=True)
    credentials = tmp_path / "credentials.json"
    credentials.write_text(
        json.dumps({"username": "file-user", "password": "file-password"})
    )
    credentials.chmod(0o644)
    monkeypatch.setenv("CALDAV_CREDENTIALS_FILE", str(credentials))
    with pytest.raises(PublicError):
        Config.from_env(discovery=True)
    credentials.chmod(0o600)
    cfg = Config.from_env(discovery=True)
    assert cfg.username == "file-user" and cfg.password == "file-password"
    credentials.write_text("not json")
    with pytest.raises(PublicError):
        Config.from_env(discovery=True)


@pytest.mark.parametrize(
    "value",
    [
        "2026-10-20 14:00:00+09:00",
        "2026-10-20T14:00:00",
        "2026-02-30",
        "2026-10-20T14:00:00+99:00",
    ],
)
def test_ambiguous_or_invalid_dates(value):
    with pytest.raises(PublicError):
        parse_time(value)
