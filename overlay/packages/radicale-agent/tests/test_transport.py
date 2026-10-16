import os
import pwd
import shutil
import subprocess
import sys
from ctypes.util import find_library
from pathlib import Path

import pytest
from dbus_next.errors import AuthError
from radicale_agent import transport


async def test_bus_auth_failure_is_sanitized(monkeypatch):
    class DeniedBus:
        async def connect(self):
            raise AuthError("private bus failure details")

    monkeypatch.setattr(transport, "MessageBus", DeniedBus)
    result = await transport.read("list_collections", {})
    assert result["error"]["code"] == "BROKER_UNAVAILABLE"
    assert "private bus" not in str(result)


def test_private_dbus_and_mcp_stdio_roundtrip(tmp_path):
    run_private_bus(tmp_path)


def run_private_bus(tmp_path, *, live=False):
    runner = shutil.which("dbus-run-session")
    if runner is None or shutil.which("xdg-dbus-proxy") is None:
        pytest.skip("dbus-run-session and xdg-dbus-proxy required (see README)")
    command = [runner]
    # Nix's session.conf is not installed under /etc inside Pi's sandbox.
    config = Path(runner).resolve().parent.parent / "share/dbus-1/session.conf"
    if config.exists():
        command += [f"--config-file={config}"]
    command += ["--", sys.executable, str(Path(__file__).with_name("bus_roundtrip.py"))]
    env = private_bus_environment(tmp_path, os.environ)
    env["RADICALE_TRANSPORT_LIVE"] = "1" if live else "0"
    subprocess.run(command, check=True, timeout=90 if live else 45, env=env)


def private_bus_environment(tmp_path, environment):
    env = dict(environment)
    try:
        pwd.getpwuid(os.getuid())
    except KeyError:
        # dbus-daemon needs a passwd entry even in Pi's minimal filesystem.
        # Redirect libc NSS lookups in this child only: no mounts or userns.
        wrapper = env.get("RADICALE_TEST_NSS_WRAPPER") or find_library("nss_wrapper")
        if not wrapper:
            pytest.skip(
                "No passwd entry: set RADICALE_TEST_NSS_WRAPPER to libnss_wrapper.so (see README)"
            )
        passwd, group = tmp_path / "passwd", tmp_path / "group"
        passwd.write_text(f"test:x:{os.getuid()}:{os.getgid()}:test:/tmp:/bin/sh\n")
        group.write_text(f"test:x:{os.getgid()}:\n")
        env["NSS_WRAPPER_PASSWD"] = str(passwd)
        env["NSS_WRAPPER_GROUP"] = str(group)
        env["LD_PRELOAD"] = " ".join(filter(None, [wrapper, env.get("LD_PRELOAD")]))
    return env


def test_missing_passwd_uses_child_nss_wrapper(monkeypatch, tmp_path):
    def no_user(_uid):
        raise KeyError

    monkeypatch.setattr(pwd, "getpwuid", no_user)
    original = {
        "RADICALE_TEST_NSS_WRAPPER": "/test/libnss_wrapper.so",
        "LD_PRELOAD": "/test/existing.so",
    }
    env = private_bus_environment(tmp_path, original)
    assert env["LD_PRELOAD"] == "/test/libnss_wrapper.so /test/existing.so"
    assert (
        Path(env["NSS_WRAPPER_PASSWD"])
        .read_text()
        .startswith(f"test:x:{os.getuid()}:{os.getgid()}:")
    )
    assert Path(env["NSS_WRAPPER_GROUP"]).read_text() == f"test:x:{os.getgid()}:\n"
    assert "NSS_WRAPPER_PASSWD" not in original


def test_existing_passwd_needs_no_wrapper(monkeypatch, tmp_path):
    monkeypatch.setattr(pwd, "getpwuid", lambda _uid: object())
    original = {"PATH": "/test/bin"}
    assert private_bus_environment(tmp_path, original) == original
    assert list(tmp_path.iterdir()) == []
