"""Validated broker requests; validation happens on the trusted host."""

import re
from datetime import date, datetime, time, timezone
from typing import Annotated, Literal
from zoneinfo import ZoneInfo

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, model_validator

from .errors import PublicError

CollectionId = Literal["Agent"]
UID = Annotated[
    str, Field(min_length=1, max_length=1024, pattern=r"^[^\x00-\x1f\x7f]+$")
]
Limit = Annotated[int, Field(ge=1, le=200)]
Title = Annotated[str, Field(min_length=1, max_length=500)]
Description = Annotated[str, Field(max_length=16384)]
Location = Annotated[str, Field(max_length=2048)]
Priority = Annotated[int, Field(ge=0, le=9)]
Percent = Annotated[int, Field(ge=0, le=100)]
Status = Literal["NEEDS-ACTION", "IN-PROCESS", "COMPLETED", "CANCELLED"]
ETag = Annotated[str, Field(pattern=r'^"[^"\x00-\x20\x7f]+"$', max_length=512)]
RequestId = Annotated[
    str,
    Field(pattern=r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"),
]


def parse_time(value: str) -> date | datetime:
    try:
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
            return date.fromisoformat(value)
        if not re.fullmatch(
            r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})", value
        ):
            raise ValueError
        result = datetime.fromisoformat(value)
        if result.utcoffset() is None:
            raise ValueError
        return result
    except ValueError as exc:
        raise PublicError(
            "INVALID_INPUT",
            "Use an ISO date or RFC 3339 timestamp with an explicit offset.",
        ) from exc


def valid_time(value: str) -> str:
    parse_time(value)
    return value


Timestamp = Annotated[
    str, Field(min_length=10, max_length=40), AfterValidator(valid_time)
]


def event_times(start: str, end: str):
    a, b = parse_time(start), parse_time(end)
    if type(a) is not type(b) or b <= a:
        raise PublicError(
            "INVALID_INPUT",
            "Event start/end must have matching date types and end must be later than start.",
        )
    return a, b


def instant(value: date | datetime, tz: ZoneInfo) -> datetime:
    if not isinstance(value, datetime):
        value = datetime.combine(value, time(), tzinfo=tz)
    return value.astimezone(timezone.utc)


class Request(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class CollectionRequest(Request):
    collection_id: CollectionId


class GetRequest(CollectionRequest):
    uid: UID


class EventsRequest(CollectionRequest):
    start: Timestamp
    end: Timestamp
    limit: Limit = 200


class TasksRequest(CollectionRequest):
    include_completed: bool = False
    due_before: Timestamp | None = None
    limit: Limit = 200


class CreateEvent(CollectionRequest):
    request_id: RequestId
    title: Title
    start: Timestamp
    end: Timestamp
    description: Description = ""
    location: Location = ""

    @model_validator(mode="after")
    def validate_times(self):
        event_times(self.start, self.end)
        return self


class CreateTask(CollectionRequest):
    request_id: RequestId
    title: Title
    due: Timestamp | None = None
    description: Description = ""
    priority: Priority = 0


class EventChanges(Request):
    title: Title | None = None
    start: Timestamp | None = None
    end: Timestamp | None = None
    description: Description | None = None
    location: Location | None = None

    @model_validator(mode="after")
    def validate_changes(self):
        if not self.model_fields_set or any(
            getattr(self, key) is None for key in self.model_fields_set
        ):
            raise PublicError(
                "INVALID_INPUT",
                "Supply at least one change; event fields cannot be null.",
            )
        if self.start is not None and self.end is not None:
            event_times(self.start, self.end)
        return self


class TaskChanges(Request):
    title: Title | None = None
    due: Timestamp | None = None
    description: Description | None = None
    priority: Priority | None = None
    status: Status | None = None
    percent_complete: Percent | None = None

    @model_validator(mode="after")
    def validate_changes(self):
        if not self.model_fields_set or any(
            getattr(self, key) is None for key in self.model_fields_set - {"due"}
        ):
            raise PublicError(
                "INVALID_INPUT", "Supply at least one change; only due may be null."
            )
        if (
            self.status is not None
            and self.percent_complete is not None
            and (
                (self.status == "COMPLETED") != (self.percent_complete == 100)
                or self.status == "NEEDS-ACTION"
                and self.percent_complete != 0
            )
        ):
            raise PublicError(
                "INVALID_INPUT", "Task status and percent_complete are inconsistent."
            )
        return self


class CompleteTask(GetRequest):
    expected_etag: ETag


class DeleteItem(GetRequest):
    expected_etag: ETag


class UpdateEvent(CompleteTask):
    changes: EventChanges


class UpdateTask(CompleteTask):
    changes: TaskChanges


READ_REQUESTS = {
    "list_collections": Request,
    "list_events": EventsRequest,
    "get_event": GetRequest,
    "list_tasks": TasksRequest,
    "get_task": GetRequest,
}
WRITE_REQUESTS = {
    "create_event": CreateEvent,
    "update_event": UpdateEvent,
    "create_task": CreateTask,
    "update_task": UpdateTask,
    "complete_task": CompleteTask,
    "delete_event": DeleteItem,
    "delete_task": DeleteItem,
}
REQUESTS = READ_REQUESTS | WRITE_REQUESTS
