from contextlib import contextmanager
from types import SimpleNamespace
from zoneinfo import ZoneInfo

from icalendar import Calendar
from radicale_agent.config import Config
from radicale_agent.dav import DavBackend
from radicale_agent.errors import PublicError

ICS = """BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//radicale-agent tests//EN
BEGIN:VEVENT
UID:event-1
DTSTART;TZID=Asia/Tokyo:20261020T140000
DTEND;TZID=Asia/Tokyo:20261020T150000
SUMMARY:Untrusted event title
END:VEVENT
BEGIN:VEVENT
UID:all-day
DTSTART;VALUE=DATE:20261021
DTEND;VALUE=DATE:20261023
SUMMARY:All day
END:VEVENT
BEGIN:VTODO
UID:task-1
SUMMARY:Test task
DUE;VALUE=DATE:20261022
PRIORITY:3
STATUS:NEEDS-ACTION
END:VTODO
BEGIN:VTODO
UID:task-done
SUMMARY:Done
STATUS:COMPLETED
PERCENT-COMPLETE:100
COMPLETED:20261020T050000Z
END:VTODO
END:VCALENDAR
"""


def config():
    return Config(
        "https://dav.example.test/",
        "private-user",
        "private-password",
        {"Agent": "https://dav.example.test/user/test/"},
        ZoneInfo("Asia/Tokyo"),
    )


class Resource:
    etag = '"test-etag"'

    def __init__(self, ics=ICS):
        self.ics = ics

    def get_icalendar_instance(self):
        return Calendar.from_ical(self.ics)


class Collection:
    url = "https://dav.example.test/user/test/"
    components = ("VEVENT", "VTODO")

    def get_display_name(self):
        return "Agent"

    def get_supported_components(self):
        return self.components

    def search(self, **kwargs):
        self.query = kwargs
        return [Resource()]

    def get_event_by_uid(self, uid):
        return Resource()

    get_todo_by_uid = get_event_by_uid


class StoredResource:
    def __init__(self, uid):
        self.uid = uid
        self.url = "https://dav.example.test/user/test/" + uid + ".ics"
        self.etag = None
        self.data = b""

    def get_icalendar_instance(self):
        return Calendar.from_ical(self.data)


class WritableBackend:
    describe = staticmethod(DavBackend.describe)

    def __init__(self):
        self.connections = self.puts = self.deletes = 0
        self.before_put = self.before_delete = None
        self.store = {}
        self.collection = Collection()
        self.collection.search = lambda **kw: [
            self.reload(StoredResource(uid)) for uid in self.store
        ]
        self.collection.get_event_by_uid = self.lookup
        self.collection.get_todo_by_uid = self.lookup
        for component in Calendar.from_ical(ICS).subcomponents:
            instance = Calendar()
            instance.add_component(component)
            self.store[str(component["UID"])] = (instance.to_ical(), '"seed"')

    def lookup(self, uid):
        return self.reload(StoredResource(uid))

    @contextmanager
    def connect(self):
        self.connections += 1
        yield object()

    def calendars(self, client):
        return [self.collection]

    def lookup_item(self, calendar, kind, uid):
        return self.lookup(uid)

    def delete(self, calendar, resource, expected_etag):
        if self.before_delete is not None:
            callback, self.before_delete = self.before_delete, None
            callback(resource.uid)
        if resource.uid not in self.store:
            raise PublicError("NOT_FOUND", "Fixture not found")
        if self.store[resource.uid][1] != expected_etag:
            raise PublicError("CONFLICT", "Fixture precondition failed")
        del self.store[resource.uid]
        self.deletes += 1

    def new_resource(self, calendar, kind, uid):
        return StoredResource(uid)

    def reload(self, resource):
        if resource.uid not in self.store:
            raise PublicError("NOT_FOUND", "Fixture not found")
        resource.data, resource.etag = self.store[resource.uid]
        return resource

    def put(self, calendar, resource, instance, expected_etag=None):
        if self.before_put is not None:
            callback, self.before_put = self.before_put, None
            callback(resource.uid)
        existing = self.store.get(resource.uid)
        if (
            expected_etag is None
            and existing is not None
            or expected_etag is not None
            and (existing is None or existing[1] != expected_etag)
        ):
            raise PublicError("CONFLICT", "Fixture precondition failed")
        self.puts += 1
        self.store[resource.uid] = (instance.to_ical(), f'"version-{self.puts}"')
        return self.reload(resource)


class Backend:
    describe = staticmethod(DavBackend.describe)
    reload = staticmethod(lambda resource: resource)

    def __init__(self):
        self.connections = 0
        self.collection = Collection()

    @contextmanager
    def connect(self):
        self.connections += 1
        yield object()

    def calendars(self, client):
        # Even metadata of the unauthorized collection must not be fetched.
        return [
            self.collection,
            SimpleNamespace(url="https://dav.example.test/user/private/"),
        ]
