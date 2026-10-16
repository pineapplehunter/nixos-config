import threading
from dataclasses import replace
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
from radicale_agent.dav import DavBackend
from radicale_agent.errors import PublicError
from support import config


@pytest.mark.parametrize(
    "status,code",
    [
        (401, "AUTH_FAILED"),
        (403, "FORBIDDEN"),
        (404, "NOT_FOUND"),
        (412, "CONFLICT"),
        (503, "SERVER_UNAVAILABLE"),
        (302, "SERVER_UNAVAILABLE"),
    ],
)
def test_real_client_http_error_mapping(status, code):
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_OPTIONS(self):
            requests.append(self.path)
            self.send_response(status)
            if status == 302:
                self.send_header(
                    "Location", "http://127.0.0.1:1/redirect-must-not-be-followed"
                )
            self.end_headers()
            self.wfile.write(b"private server error body")

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        cfg = replace(config(), url=f"http://127.0.0.1:{server.server_port}/")
        with pytest.raises(PublicError) as error, DavBackend(cfg).connect() as client:
            client.options(cfg.url)
        assert error.value.code == code
        assert len(requests) == 1
        assert "private" not in error.value.message
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


def test_conditional_writes_and_deletes_are_enforced_by_http_server():
    from caldav import Calendar as DavCalendar
    from icalendar import Calendar
    from support import ICS

    state = {"data": None, "etag": None, "headers": [], "delete_headers": []}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200 if state["data"] else 404)
            if state["etag"]:
                self.send_header("ETag", state["etag"])
            self.end_headers()
            self.wfile.write(state["data"] or b"")

        def do_PUT(self):
            body = self.rfile.read(int(self.headers["Content-Length"]))
            state["headers"].append(
                (self.headers.get("If-Match"), self.headers.get("If-None-Match"))
            )
            if (
                self.headers.get("If-None-Match") == "*"
                and state["data"] is not None
                or self.headers.get("If-Match")
                and self.headers["If-Match"] != state["etag"]
            ):
                self.send_response(412)
            else:
                self.send_response(201 if state["data"] is None else 204)
                state["data"], state["etag"] = body, f'"v{len(state["headers"])}"'
                self.send_header("ETag", state["etag"])
            self.end_headers()

        def do_DELETE(self):
            state["delete_headers"].append(self.headers.get("If-Match"))
            if self.headers.get("If-Match") != state["etag"]:
                self.send_response(412)
            else:
                state["data"] = state["etag"] = None
                self.send_response(204)
            self.end_headers()

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        url = f"http://127.0.0.1:{server.server_port}/"
        cfg = replace(
            config(), url=url, allowed={"Agent": url + "Agent/"}, writes_enabled=True
        )
        backend = DavBackend(cfg)
        with backend.connect() as client:
            calendar = DavCalendar(client=client, url=cfg.allowed["Agent"])
            resource = backend.new_resource(calendar, "VEVENT", "agent-test")
            instance = Calendar.from_ical(ICS)
            backend.put(calendar, resource, instance)
            assert resource.etag == '"v1"'
            with pytest.raises(PublicError) as error:
                backend.put(calendar, resource, instance)
            assert error.value.code == "CONFLICT"
            with pytest.raises(PublicError) as error:
                backend.put(calendar, resource, instance, '"stale"')
            assert error.value.code == "CONFLICT"
            backend.put(calendar, resource, instance, '"v1"')
            assert state["headers"] == [
                (None, "*"),
                (None, "*"),
                ('"stale"', None),
                ('"v1"', None),
            ]
            with pytest.raises(PublicError) as error:
                backend.delete(calendar, resource, '"stale"')
            assert error.value.code == "CONFLICT" and state["data"] is not None
            backend.delete(calendar, resource, '"v4"')
            assert state["delete_headers"] == ['"stale"', '"v4"']
            with pytest.raises(PublicError) as error:
                backend.reload(resource)
            assert error.value.code == "NOT_FOUND"
            for headers in ({}, {"If-None-Match": "*"}):
                with pytest.raises(PublicError) as error:
                    client.request(str(resource.url), "DELETE", headers=headers)
                assert error.value.code == "CONFLICT"
            with pytest.raises(PublicError) as error:
                client.request(
                    url + "private/x.ics", "DELETE", headers={"If-Match": '"v4"'}
                )
            assert error.value.code == "FORBIDDEN"
            for target, headers, code in [
                (cfg.allowed["Agent"] + "x.ics", {}, "CONFLICT"),
                (url + "private/x.ics", {"If-None-Match": "*"}, "FORBIDDEN"),
            ]:
                with pytest.raises(PublicError) as error:
                    client.put(target, instance.to_ical(), headers)
                assert error.value.code == code
            for method in ("DELETE", "MKCALENDAR", "PROPPATCH"):
                with pytest.raises(PublicError):
                    client.request(cfg.allowed["Agent"], method)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


def test_client_blocks_writes_and_cross_origin():
    with DavBackend(config()).connect() as client:
        for method in ("PUT", "DELETE", "MKCALENDAR", "PROPPATCH"):
            with pytest.raises(PublicError) as err:
                client.request(config().url, method)
            assert err.value.code == "READ_ONLY"
        with pytest.raises(PublicError) as err:
            client.request("https://evil.test/", "GET")
        assert err.value.code == "FORBIDDEN"
