"""Bubblewrap launcher for Pi, including its filtered portal identity."""

import asyncio
import grp
import hashlib
import json
import os
import pwd
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import tomllib
from pathlib import Path
from typing import BinaryIO, NoReturn
from urllib.parse import unquote

from dbus_next import DBusError, Message, MessageType
from dbus_next.aio import MessageBus

APP_ID = "io.github.pineapplehunter.Pi"
PORTAL = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
MCP_BUS_NAMES = ()  # configured by Home Manager


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


def flatten_args(groups: list[str | list[str]]) -> list[str]:
    return [
        arg for group in groups
        for arg in ([group] if isinstance(group, str) else group)
    ]


def add_bind(
    args: list[str | list[str]],
    option: str,
    source: Path | str,
    destination: Path | str,
) -> None:
    args.append([option, str(source), str(destination)])


def add_copy(
    args: list[str | list[str]],
    files: list[BinaryIO],
    source: Path | str,
    destination: Path | str,
) -> None:
    """Copy a file into the private filesystem, without a host bind mount."""
    stream = Path(source).open("rb")
    files.append(stream)
    args.append(["--file", str(stream.fileno()), str(destination)])


def portal_mount() -> Path | None:
    """Activate the document portal and return its host FUSE mount."""

    async def mount():
        connection = MessageBus()
        try:
            await connection.connect()
            reply = await connection.call(
                Message(
                    destination="org.freedesktop.portal.Documents",
                    path="/org/freedesktop/portal/documents",
                    interface="org.freedesktop.portal.Documents",
                    member="GetMountPoint",
                )
            )
            if reply.message_type == MessageType.ERROR:
                raise DBusError._from_message(reply)
            raw = bytes(reply.body[0]).rstrip(b"\0")
            return Path(os.fsdecode(raw)) / "by-app" / APP_ID
        finally:
            connected = connection.connected
            connection.disconnect()
            if connected:
                await connection.wait_for_disconnect()

    async def run():
        return await asyncio.wait_for(mount(), 5)

    try:
        return asyncio.run(run())
    except (DBusError, OSError, TimeoutError) as error:
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


def protect_ticket_config(bwrap: list[str | list[str]], home: Path) -> None:
    private = (home / ".config/pi-remote").resolve()
    for arg in bwrap:
        if isinstance(arg, list) and arg[0] in {
            "--ro-bind", "--ro-bind-try", "--bind", "--dev-bind",
        }:
            source = Path(arg[1]).resolve()
            if (source.is_relative_to(private)
                    or private.is_relative_to(source)):
                raise RuntimeError("cannot mount Pi Remote host configuration")


def parse_wrapper_args(
    arguments: list[str], bwrap: list[str | list[str]]
) -> tuple[bool, bool, list[str]]:
    debug = False
    noflake = False
    index = 0
    while index < len(arguments) and arguments[index].startswith("@"):
        argument = arguments[index]
        if argument == "@@":
            index += 1
            break
        if argument == "@debug-shell":
            debug = True
            index += 1
        elif argument == "@noflake":
            noflake = True
            index += 1
        elif argument == "@dev":
            bwrap.extend([
                ["--dev-bind", "/dev", "/dev"],
                ["--ro-bind", "/sys", "/sys"],
            ])
            index += 1
        elif argument in {"@allow", "@allow-rw"}:
            if index + 1 >= len(arguments):
                fail(f"{argument} requires a path")
            path = Path(arguments[index + 1]).resolve(strict=True)
            option = "--ro-bind" if argument == "@allow" else "--bind"
            add_bind(bwrap, option, path, path)
            index += 2
        else:
            fail(f"error while processing wrapping argument {argument}")
    return debug, noflake, arguments[index:]


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
    if not os.environ.get("PI_GIT_CONFIG"):
        fail("PI_GIT_CONFIG is not set")
    runtime_text = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_text:
        fail("XDG_RUNTIME_DIR is not set")

    home = Path.home()
    runtime = Path(runtime_text)
    nix_proxy_dir = runtime / "pi-nix-daemon"
    nix_proxy_socket = nix_proxy_dir / "socket"
    if not nix_proxy_socket.is_socket():
        fail(
            f"Nix proxy socket not found: {nix_proxy_socket}; "
            "run 'systemctl --user start pi-nix-daemon.socket' on the host"
        )
    extra_binds: list[str | list[str]] = []
    debug, noflake, arguments = parse_wrapper_args(sys.argv[1:], extra_binds)
    root = Path.cwd() if noflake else project_root(marker)
    has_wayland_clipboard = bool(os.environ.get("WAYLAND_DISPLAY"))
    (home / ".pi").mkdir(parents=True, exist_ok=True)
    (home / ".cache/nix").mkdir(parents=True, exist_ok=True)

    agent_dir = home / ".pi/agent"

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
    ticket_socket = proxy_socket.with_suffix(".ticket")
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
    proxy_bwrap: list[str | list[str]] = [
        "--unshare-all",
        "--share-net",
        "--die-with-parent",
        ["--cap-drop", "ALL"],
        ["--dev", "/dev"],
        ["--proc", "/proc"],
        ["--ro-bind", "/nix/store", "/nix/store"],
        ["--dir", str(runtime)],
    ]
    if host_bus_socket is not None:
        add_bind(proxy_bwrap, "--ro-bind", host_bus_socket, host_bus_socket)
    proxy_bwrap.extend([
        ["--bind", str(proxy_dir), str(proxy_dir)],
        ["--ro-bind", str(metadata_path), "/.flatpak-info"],
        "--clearenv",
        ["--setenv", "XDG_RUNTIME_DIR", str(runtime)],
    ])
    proxy_command = [
        proxy_binary, host_bus, str(proxy_socket),
        f"--fd={lifetime_child.fileno()}",
        "--filter",
        "--call=io.github.pineapplehunter.LocalClipboard1=io.github.pineapplehunter.LocalClipboard1.Copy@/io/github/pineapplehunter/LocalClipboard1",  # noqa: E501
        "--call=io.github.pineapplehunter.GitSign1=io.github.pineapplehunter.GitSign1.SignCommit@/io/github/pineapplehunter/GitSign1",  # noqa: E501
    ]
    if os.environ.get("PI_GITHUB_FETCH_ENABLED") == "1":
        proxy_command.append(
            "--call=io.github.pineapplehunter.GitHubFetch1=io.github.pineapplehunter.GitHubFetch1.Run@/io/github/pineapplehunter/GitHubFetch1"  # noqa: E501
        )
    ticket = "io.github.pineapplehunter.PiRemoteTicket1"
    ticket_rule = (f"--call={ticket}={ticket}.RequestTicket"
                   "@/io/github/pineapplehunter/PiRemoteTicket1")
    proxy_command.append(ticket_rule)
    proxy_command.extend(
        f"--call={name}=io.github.pineapplehunter.Mcp1.{method}@/io/github/pineapplehunter/Mcp1"  # noqa: E501
        for name in MCP_BUS_NAMES
        for method in ["Open", "Send", "Receive", "Close"]
    )
    proxy_command.extend([
        f"--call={PORTAL}=org.freedesktop.portal.FileChooser.OpenFile@{PORTAL_PATH}",  # noqa: E501
        f"--call={PORTAL}=org.freedesktop.portal.Request.Close@{PORTAL_PATH}/request/*",  # noqa: E501
        f"--broadcast={PORTAL}=org.freedesktop.portal.Request.Response@{PORTAL_PATH}/request/*",  # noqa: E501
    ])
    # A second listener, not a chain: each address/path pair has its own
    # policy. Workers never receive the broader parent listener.
    proxy_command.extend([host_bus, str(ticket_socket), "--filter",
                          ticket_rule])
    proxy = subprocess.Popen(
        ["bwrap", *flatten_args(proxy_bwrap), "--", *proxy_command],
        pass_fds=(lifetime_child.fileno(),),
    )
    lifetime_child.close()
    child: subprocess.Popen | None = None
    sandbox_files: list[BinaryIO] = []

    def cleanup() -> None:
        for stream in sandbox_files:
            stream.close()
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
        ticket_socket.unlink(missing_ok=True)
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
        while not (proxy_socket.is_socket() and ticket_socket.is_socket()):
            if proxy.poll() is not None:
                fail("Failed to start the D-Bus proxy")
            if time.monotonic() >= deadline:
                fail("Timed out waiting for the D-Bus proxy")
            time.sleep(0.01)

        # Resolve the host identity before entering the sandbox, which has no
        # host account database. Only expose root and the launching user/group.
        uid, gid = os.getuid(), os.getgid()
        user = pwd.getpwuid(uid)
        group = grp.getgrgid(gid)
        passwd = "root:x:0:0:root:/root:/bin/sh\n" if uid != 0 else ""
        passwd += f"{user.pw_name}:x:{uid}:{gid}::{home}:/bin/sh\n"
        groups = "root:x:0:\n" if gid != 0 else ""
        groups += f"{group.gr_name}:x:{gid}:{user.pw_name}\n"
        generated = {
            "passwd": passwd,
            "group": groups,
            # Host systemd/mDNS NSS modules have no services in the sandbox.
            "nsswitch.conf": (
                "passwd: files\ngroup: files\nshadow: files\n"
                "hosts: files dns\nnetworks: files\n"
                "services: files\nprotocols: files\nrpc: files\n"
            ),
            "host.conf": "multi on\n",
        }
        for name, content in generated.items():
            atomic_write(instance_dir / name, content.encode(), 0o444)

        bwrap: list[str | list[str]] = [
            "--unshare-all",
            "--die-with-parent",
            ["--cap-drop", "ALL"],
            "--share-net",
            ["--dev", "/dev"],
            ["--proc", "/proc"],
            ["--tmpfs", "/nix"],
            ["--ro-bind", "/nix/store", "/nix/store"],
            ["--tmpfs", str(home)],
            ["--tmpfs", "/etc"],
            ["--tmpfs", "/run"],
            ["--dir", "/run/user"],
            ["--dir", str(runtime)],
            # Bind the directory so socket recreation is visible to clients.
            ["--ro-bind", str(nix_proxy_dir), "/nix/var/nix/daemon-socket"],
            # A writable state directory makes Nix auto-select a local store.
            ["--remount-ro", "/nix"],
            ["--ro-bind", str(proxy_socket), str(runtime / "bus")],
            ["--ro-bind", str(ticket_socket), "/run/pi-subagent/ticket-bus"],
            ["--ro-bind", str(metadata_path), "/.flatpak-info"],
            ["--tmpfs", "/var"],
            ["--bind", str(home / ".pi"), str(home / ".pi")],
            ["--bind", str(home / ".cache/nix"), str(home / ".cache/nix")],
            ["--bind", str(root), str(root)],
            "--clearenv",
        ]
        codex_host = os.environ.get("PI_CODEX_HOST_ENABLED") == "1"
        if codex_host:
            broker_dir = runtime / "pi-codex-host"
            if broker_dir.is_dir():
                add_bind(bwrap, "--ro-bind", broker_dir, "/run/pi-codex-host")
            # A missing socket must not reactivate sandbox image OAuth.
            bwrap.append([
                "--setenv", "PI_CODEX_HOST_SOCKET",
                "/run/pi-codex-host/broker.sock",
            ])
        # No SSH keys or agent socket are mounted; the host selects its own
        # signing key through filtered D-Bus.
        if has_wayland_clipboard:
            # Pi uses WAYLAND_DISPLAY only to select its wl-copy backend. The
            # compatibility client talks to the host broker, not to Wayland.
            bwrap.append(["--setenv", "WAYLAND_DISPLAY", "pi-clipboard"])
        documents = portal_mount()
        if documents is not None and documents.is_dir():
            bwrap.extend([
                ["--dir", "/run/flatpak"],
                ["--ro-bind", str(documents), "/run/flatpak/doc"],
                ["--bind", str(documents), "/run/flatpak/doc-rw"],
                ["--symlink", "/run/flatpak/doc", str(runtime / "doc")],
            ])
        environment = {
            "LANG": "C",
            "HOME": str(home),
            "PWD": str(Path.cwd()),
            "XDG_RUNTIME_DIR": str(runtime),
            "DBUS_SESSION_BUS_ADDRESS": f"unix:path={runtime}/bus",
            "PI_CODING_AGENT_DIR": str(agent_dir),
            "PI_CODING_AGENT_SESSION_DIR": str(agent_dir / "sessions"),
            "GIT_CONFIG_GLOBAL": os.environ["PI_GIT_CONFIG"],
            "GIT_CONFIG_NOSYSTEM": "1",
            "EDITOR": "hx",
        }
        for key, value in environment.items():
            bwrap.append(["--setenv", key, value])
        for name in generated:
            add_copy(bwrap, sandbox_files, instance_dir / name, f"/etc/{name}")
        # Preserve host network/timezone policy as per-launch snapshots.
        for entry in ("/etc/hosts", "/etc/resolv.conf", "/etc/localtime"):
            if Path(entry).is_file():
                add_copy(bwrap, sandbox_files, entry, entry)
        # Dereference /etc/static symlinks without exposing the whole tree.
        for source in Path("/etc/nix").rglob("*"):
            if source.is_file():
                add_copy(bwrap, sandbox_files, source, source)
        bundle = "/etc/ssl/certs/ca-certificates.crt"
        if Path(bundle).is_file():
            add_copy(bwrap, sandbox_files, bundle, bundle)
            for alias in (
                "/etc/ssl/certs/ca-bundle.crt",
                "/etc/pki/tls/certs/ca-bundle.crt",
            ):
                bwrap.append(["--symlink", bundle, alias])

        upki_config = Path("/etc/upki/config.toml")
        upki_cache = Path("/var/cache/upki")
        if upki_config.is_file():
            with upki_config.open("rb") as stream:
                upki_cache = Path(tomllib.load(stream)["cache-dir"])
            add_copy(bwrap, sandbox_files, upki_config, upki_config)

        for entry in ("/bin/sh", "/usr/bin/env"):
            bwrap.append(["--ro-bind-try", entry, entry])

        sandbox_path = os.environ.get("PI_SANDBOX_PATH")
        if not sandbox_path:
            raise RuntimeError("PI_SANDBOX_PATH is not set")
        for entry in sandbox_path.split(os.pathsep):
            path = Path(entry)
            if not path.is_absolute() or not path.is_dir():
                raise RuntimeError(f"Invalid sandbox PATH entry: {entry}")
        bwrap.append(["--setenv", "PATH", sandbox_path])

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
        # Mount after /tmp so a custom cache path there is not hidden.
        if upki_cache.is_dir():
            add_bind(bwrap, "--ro-bind", upki_cache, upki_cache)
        bwrap.extend(extra_binds)
        protect_ticket_config(bwrap, home)
        info_read, info_write = os.pipe()
        block_read, block_write = os.pipe()
        bwrap.extend([
            ["--info-fd", str(info_write)],
            ["--block-fd", str(block_read)],
        ])
        command = os.environ.get("SHELL", "/bin/sh") if debug else executable
        child = subprocess.Popen(
            ["bwrap", *flatten_args(bwrap), "--", command, *arguments],
            pass_fds=(
                info_write,
                block_read,
                *(stream.fileno() for stream in sandbox_files),
            ),
        )
        for stream in sandbox_files:
            stream.close()
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
