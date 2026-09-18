"""Bubblewrap launcher for Pi, including its filtered portal identity."""

import hashlib
import json
import os
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import NoReturn
from urllib.parse import unquote

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

APP_ID = "io.github.pineapplehunter.Pi"
PORTAL = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"


def fail(message: str) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def project_root(marker: str) -> Path:
    current = Path.cwd()
    while not (current / marker).is_file():
        if current.parent == current:
            fail(f"{marker} not found")
        current = current.parent
    return current


def add_bind(
    args: list[str], option: str, source: Path | str, destination: Path | str
) -> None:
    args.extend((option, str(source), str(destination)))


def portal_mount() -> Path | None:
    """Activate the document portal and return its host FUSE mount."""
    try:
        connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        reply = connection.call_sync(
            "org.freedesktop.portal.Documents",
            "/org/freedesktop/portal/documents",
            "org.freedesktop.portal.Documents",
            "GetMountPoint",
            None,
            GLib.VariantType.new("(ay)"),
            Gio.DBusCallFlags.NONE,
            5_000,
            None,
        )
        raw = bytes(reply.unpack()[0]).rstrip(b"\0")
        return Path(os.fsdecode(raw)) / "by-app" / APP_ID
    except (GLib.Error, OSError) as error:
        print(
            f"warning: Documents portal unavailable: {error}", file=sys.stderr
        )
        return None


def bus_socket_path(address: str) -> Path | None:
    """Return the filesystem socket from a D-Bus address, if it has one."""
    for candidate in address.split(";"):
        if not candidate.startswith("unix:"):
            continue
        for option in candidate.removeprefix("unix:").split(","):
            key, separator, value = option.partition("=")
            if separator and key == "path":
                return Path(unquote(value))
    return None


def flatpak_info(instance_id: str) -> bytes:
    return f"""[Application]
name={APP_ID}
runtime=org.freedesktop.Platform/x86_64/24.08
sdk=org.freedesktop.Sdk/x86_64/24.08
command=pi

[Instance]
instance-id={instance_id}

[Context]
shared=network;
""".encode()


def atomic_write(path: Path, data: bytes, mode: int = 0o600) -> None:
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.close(fd)
        except OSError:
            pass
        Path(temporary).unlink(missing_ok=True)
        raise


def read_bwrap_info(
    fd: int, process: subprocess.Popen, timeout: float = 5.0
) -> bytes:
    os.set_blocking(fd, False)
    data = bytearray()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            chunk = os.read(fd, 4096)
            if chunk:
                data.extend(chunk)
                try:
                    json.loads(data)
                    return bytes(data)
                except json.JSONDecodeError:
                    pass
            elif process.poll() is not None:
                break
        except BlockingIOError:
            pass
        if process.poll() is not None and not data:
            break
        time.sleep(0.01)
    raise RuntimeError("did not receive valid Bubblewrap process information")


def parse_wrapper_args(
    arguments: list[str], bwrap: list[str]
) -> tuple[bool, list[str]]:
    debug = False
    index = 0
    while index < len(arguments) and arguments[index].startswith("@"):
        argument = arguments[index]
        if argument == "@@":
            index += 1
            break
        if argument == "@debug-shell":
            debug = True
            index += 1
        elif argument in {"@allow", "@allow-rw"}:
            if index + 1 >= len(arguments):
                fail(f"{argument} requires a path")
            path = str(Path(arguments[index + 1]).resolve(strict=True))
            bwrap.extend(
                ("--ro-bind" if argument == "@allow" else "--bind", path, path)
            )
            index += 2
        else:
            fail(f"error while processing wrapping argument {argument}")
    return debug, arguments[index:]


def main() -> int:
    if os.environ.get("BUBBLEUNWRAP"):
        os.execvp(
            os.environ["EXECUTABLE"], [os.environ["EXECUTABLE"], *sys.argv[1:]]
        )
    executable = os.environ.get("EXECUTABLE")
    marker = os.environ.get("PROJECT_ROOT_FILE")
    if not executable:
        fail("The environment variable EXECUTABLE is not set")
    if not marker:
        fail("The environment variable PROJECT_ROOT_FILE is not set")
    runtime_text = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_text:
        fail("XDG_RUNTIME_DIR is not set")

    home = Path.home()
    runtime = Path(runtime_text)
    root = project_root(marker)
    (home / ".pi").mkdir(parents=True, exist_ok=True)
    (home / ".cache/nix").mkdir(parents=True, exist_ok=True)

    profile = os.environ.get("PI_WRAPPER_PROFILE", "personal")
    if profile == "personal":
        agent_dir = home / ".pi/agent"
    elif profile == "work":
        agent_dir = home / ".pi/agent-work"
        agent_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        for entry in (
            "AGENTS.md",
            "APPEND_SYSTEM.md",
            "SYSTEM.md",
            "extensions",
            "skills",
            "prompts",
            "themes",
            "npm",
            "git",
            "settings.json",
            "keybindings.json",
            "models.json",
            "trust.json",
            "pi-usage.json",
        ):
            source, target = home / ".pi/agent" / entry, agent_dir / entry
            if (
                source.exists()
                and not target.exists()
                and not target.is_symlink()
            ):
                target.symlink_to(source)
    else:
        fail(f"Unknown Pi wrapper profile: {profile}")

    instance_id = "pi-" + secrets.token_hex(16)
    instance_dir = runtime / ".flatpak" / instance_id
    instance_dir.mkdir(parents=True, mode=0o700)
    os.chmod(instance_dir, 0o700)
    metadata = flatpak_info(instance_id)
    metadata_path = instance_dir / "info"
    atomic_write(metadata_path, metadata, 0o400)
    atomic_write(instance_dir / "pid", f"{os.getpid()}\n".encode())

    proxy_dir = runtime / "pi-dbus-proxy"
    proxy_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(proxy_dir, 0o700)
    proxy_socket = proxy_dir / f"session-{os.getpid()}-{secrets.token_hex(8)}"
    host_bus = os.environ.get(
        "DBUS_SESSION_BUS_ADDRESS", f"unix:path={runtime}/bus"
    )
    host_bus_socket = bus_socket_path(host_bus)
    if host_bus_socket is not None and not host_bus_socket.is_socket():
        fail(f"Session bus socket not found: {host_bus_socket}")
    lifetime_parent, lifetime_child = socket.socketpair()
    proxy_binary = shutil.which("xdg-dbus-proxy")
    if proxy_binary is None:
        fail("xdg-dbus-proxy not found")
    proxy_command = [
        "bwrap",
        "--unshare-all",
        "--share-net",
        "--die-with-parent",
        "--cap-drop",
        "ALL",
        "--dev",
        "/dev",
        "--proc",
        "/proc",
        "--ro-bind",
        "/nix",
        "/nix",
        "--dir",
        str(runtime),
    ]
    if host_bus_socket is not None:
        proxy_command.extend(
            ("--ro-bind", str(host_bus_socket), str(host_bus_socket))
        )
    proxy_command.extend(
        (
            "--bind",
            str(proxy_dir),
            str(proxy_dir),
            "--ro-bind",
            str(metadata_path),
            "/.flatpak-info",
            "--clearenv",
            "--setenv",
            "XDG_RUNTIME_DIR",
            str(runtime),
            "--",
            proxy_binary,
            host_bus,
            str(proxy_socket),
            f"--fd={lifetime_child.fileno()}",
            "--filter",
            (
                "--call=io.github.pineapplehunter.LocalNotify1="
                "io.github.pineapplehunter.LocalNotify1.Notify@"
                "/io/github/pineapplehunter/LocalNotify1"
            ),
            (
                f"--call={PORTAL}=org.freedesktop.portal.OpenURI"
                f".OpenURI@{PORTAL_PATH}"
            ),
            (
                f"--call={PORTAL}=org.freedesktop.portal.FileChooser"
                f".OpenFile@{PORTAL_PATH}"
            ),
            (
                f"--call={PORTAL}=org.freedesktop.portal.Request"
                f".Close@{PORTAL_PATH}/request/*"
            ),
            (
                f"--broadcast={PORTAL}=org.freedesktop.portal.Request"
                f".Response@{PORTAL_PATH}/request/*"
            ),
        )
    )
    proxy = subprocess.Popen(
        proxy_command, pass_fds=(lifetime_child.fileno(),)
    )
    lifetime_child.close()
    child: subprocess.Popen | None = None

    def cleanup() -> None:
        if child is not None and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
        lifetime_parent.close()
        if proxy.poll() is None:
            proxy.terminate()
            try:
                proxy.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proxy.kill()
        proxy_socket.unlink(missing_ok=True)
        shutil.rmtree(instance_dir, ignore_errors=True)

    def forward(signum, _frame) -> None:
        if child is not None and child.poll() is None:
            child.send_signal(signum)

    for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, forward)

    try:
        lifetime_parent.settimeout(5)
        if lifetime_parent.recv(1) != b"x":
            fail("Failed to synchronize with the D-Bus proxy")
        lifetime_parent.settimeout(None)
        deadline = time.monotonic() + 5
        while not proxy_socket.is_socket():
            if proxy.poll() is not None:
                fail("Failed to start the D-Bus proxy")
            if time.monotonic() >= deadline:
                fail("Timed out waiting for the D-Bus proxy")
            time.sleep(0.01)

        bwrap = [
            "bwrap",
            "--unshare-all",
            "--die-with-parent",
            "--cap-drop",
            "ALL",
            "--share-net",
            "--dev",
            "/dev",
            "--proc",
            "/proc",
            "--ro-bind",
            "/nix",
            "/nix",
            "--tmpfs",
            str(home),
            "--tmpfs",
            "/etc",
            "--tmpfs",
            "/run",
            "--dir",
            "/run/user",
            "--dir",
            str(runtime),
            "--dir",
            "/run/wrappers",
            "--ro-bind",
            str(proxy_socket),
            str(runtime / "bus"),
            "--ro-bind",
            str(metadata_path),
            "/.flatpak-info",
            "--tmpfs",
            "/var",
            "--bind",
            str(home / ".pi"),
            str(home / ".pi"),
            "--bind",
            str(home / ".cache/nix"),
            str(home / ".cache/nix"),
            "--bind",
            str(root),
            str(root),
            "--clearenv",
        ]
        documents = portal_mount()
        if documents is not None and documents.is_dir():
            bwrap.extend(
                (
                    "--dir",
                    "/run/flatpak",
                    "--ro-bind",
                    str(documents),
                    "/run/flatpak/doc",
                )
            )
            bwrap.extend(
                ("--symlink", "/run/flatpak/doc", str(runtime / "doc"))
            )
        bwrap.extend(
            (
                "--setenv",
                "LANG",
                "C",
                "--setenv",
                "HOME",
                str(home),
                "--setenv",
                "PWD",
                str(Path.cwd()),
                "--setenv",
                "XDG_RUNTIME_DIR",
                str(runtime),
                "--setenv",
                "DBUS_SESSION_BUS_ADDRESS",
                f"unix:path={runtime}/bus",
                "--setenv",
                "PI_CODING_AGENT_DIR",
                str(agent_dir),
                "--setenv",
                "PI_CODING_AGENT_SESSION_DIR",
                str(home / ".pi/agent/sessions"),
                "--setenv",
                "PI_WRAPPER_PROFILE",
                profile,
                "--setenv",
                "PUEUE_CONFIG_PATH",
                os.environ.get("PUEUE_CONFIG_PATH", ""),
                "--setenv",
                "GIT_AUTHOR_NAME",
                "pi-coding-agent",
                "--setenv",
                "GIT_AUTHOR_EMAIL",
                "peshogo+agent@gmail.com",
                "--setenv",
                "GIT_COMMITTER_NAME",
                "pi-coding-agent",
                "--setenv",
                "GIT_COMMITTER_EMAIL",
                "peshogo+agent@gmail.com",
                "--setenv",
                "EDITOR",
                "hx",
            )
        )
        for entry in (
            "/bin/sh",
            "/etc/gai.conf",
            "/etc/host.conf",
            "/etc/hosts",
            "/etc/localtime",
            "/etc/nix",
            "/etc/nsswitch.conf",
            "/etc/pki",
            "/etc/resolv.conf",
            "/etc/ssl",
            "/etc/static",
            "/usr/bin/env",
        ):
            bwrap.extend(("--ro-bind-try", entry, entry))

        sandbox_path: list[str] = []
        for entry in os.environ.get("PATH", "").split(os.pathsep):
            if entry and Path(entry).exists():
                resolved = str(Path(entry).resolve(strict=True))
                sandbox_path.append(resolved)
                if resolved.startswith("/run/"):
                    bwrap.extend(("--dir", resolved))
                bwrap.extend(("--ro-bind-try", resolved, resolved))
        bwrap.extend(("--setenv", "PATH", os.pathsep.join(sandbox_path)))

        git_file = root / ".git"
        if git_file.is_file():
            git_dir_text = (
                git_file.read_text().strip().removeprefix("gitdir: ")
            )
            git_dir = (root / git_dir_text).resolve()
            common = (git_dir / "commondir").read_text().strip()
            common_dir = (git_dir / common).resolve()
            add_bind(bwrap, "--bind", common_dir, common_dir)

        # Preserve the former shell wrapper's newline-terminated hash input.
        digest = hashlib.sha256(f"{root}\n".encode()).hexdigest()
        sandbox_tmp = home / ".local/share/pi-tmp" / digest
        sandbox_tmp.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(sandbox_tmp, 0o700)
        add_bind(bwrap, "--bind", sandbox_tmp, sandbox_tmp)
        add_bind(bwrap, "--bind", sandbox_tmp, "/tmp")

        debug, arguments = parse_wrapper_args(sys.argv[1:], bwrap)
        info_read, info_write = os.pipe()
        block_read, block_write = os.pipe()
        bwrap.extend(
            ("--info-fd", str(info_write), "--block-fd", str(block_read), "--")
        )
        command = os.environ.get("SHELL", "/bin/sh") if debug else executable
        child = subprocess.Popen(
            [*bwrap, command, *arguments],
            pass_fds=(info_write, block_read),
        )
        os.close(info_write)
        os.close(block_read)
        info = read_bwrap_info(info_read, child)
        os.close(info_read)
        parsed = json.loads(info)
        if (
            not isinstance(parsed.get("child-pid"), int)
            or parsed["child-pid"] <= 0
        ):
            raise RuntimeError("Bubblewrap did not report a child PID")
        atomic_write(instance_dir / "bwrapinfo.json", info)
        os.write(block_write, b"1")
        os.close(block_write)
        return child.wait()
    except (OSError, RuntimeError, json.JSONDecodeError) as error:
        print(f"bubble-wrapper: {error}", file=sys.stderr)
        return 1
    finally:
        cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
