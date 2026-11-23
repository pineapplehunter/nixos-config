"""Launch named Pi tasks with native sessions and supplied workspaces."""

import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import tomllib
import uuid

THINKING_LEVELS = ("off", "minimal", "low", "medium", "high", "xhigh", "max")
STATE_ROOT = Path("/tmp/pi-subagent-state")
NIX_DAEMON_DIR = "/nix/var/nix/daemon-socket"
SUBAGENT_RUNNER = (
    "@SUBAGENT_RUNNER@"
    "/bin/pi-subagent-runner"
)
PINNED_EXTENSIONS = ("pueue-tool", "subagent-pueue")
CODEX_HOST = "codex-host"
CODEX_SOCKET_ENV = "PI_CODEX_HOST_SOCKET"
CODEX_SOCKET = Path("/run/pi-codex-host/broker.sock")
CHILD_INSTRUCTIONS = """You are a subagent of the parent Pi agent.
Your working directory is a caller-prepared, possibly incomplete workspace
mounted at the original project path. The original project is not accessible.
The workspace can change between turns: reread relevant files before editing.
You inherit the parent's environment, authentication, and settings. Built-in
tool selection is unchanged. Your supplied project is trusted by default.
Your ~/.pi resources are writable tmpfs overlays: changes there are discarded
when this process exits and never propagate to the parent. Symlink targets in
the Nix store remain immutable; replace the link with a copy if you need edits.
The Nix store, untrusted Nix daemon proxy, and networking are available.
Your Pueue daemon is private to this sandbox. Every task completion starts
another turn, or queues a follow-up if you are busy. Do independent work, then
end your response naturally when only background tasks remain; do not wait or
poll. You remain alive until all tasks finish and you process their completion
notifications. Inspect task logs when needed, and continue the original task.
Your conversation is saved separately in /run/pi-subagent/sessions.
Write your final report to /run/pi-subagent/response.md after processing all
results, before ending your final response. Intermediate responses are not
final.
The parent reads that file, not your ordinary final message. Include concise
results, test outcomes, and changed files using project-relative paths.
If inputs are missing, report exactly what the parent should provide before
resuming you. Do not invoke or create other subagents.
"""


def extension_path(agent_source, name):
    extensions = agent_source / "npm/node_modules/pi-customizations/extensions"
    return extensions / name / "index.ts"


@contextlib.contextmanager
def lock(directory, name):
    with (directory / name).open("a") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("Session is busy") from None
        yield


def ensure_idle(directory, session_id):
    with lock(directory, "execution.lock"):
        result = subprocess.run(
            ["pueue", "status", "--json"],
            check=True,
            capture_output=True,
            text=True,
        )
        for task in json.loads(result.stdout)["tasks"].values():
            if not (task.get("label") or "").startswith(
                f"subagent:{session_id}:"
            ):
                continue
            status = task["status"]
            if not (isinstance(status, dict) and "Done" in status):
                raise ValueError(f"Session task is not finished: {status}")


def defaults(options, state, agent_source):
    config_path = agent_source / "subagents.json"
    saved = state / "selection.json"
    if options.resume and not options.profile and saved.is_file():
        preset = json.loads(saved.read_text())
    else:
        config = (
            json.loads(config_path.read_text()) if config_path.exists() else {}
        )
        if not isinstance(config, dict):
            raise ValueError(f"{config_path}: expected an object")
        if "profiles" in config:
            profiles = config["profiles"]
            name = options.profile or config.get("defaultProfile")
            if not isinstance(profiles, dict) or name not in profiles:
                raise ValueError(f"Unknown subagent profile: {name}")
            preset = profiles[name]
        elif options.profile:
            raise ValueError("Configure named presets with /subagents first")
        else:
            preset = config  # Legacy single-model configuration.
    if not isinstance(preset, dict):
        raise ValueError("Subagent preset must be an object")
    options.model = preset.get("model")
    options.thinking = preset.get("thinkingLevel", "off")
    if (
        not isinstance(options.model, str)
        or not re.fullmatch(r"[^/\s]+/\S+", options.model)
    ):
        raise ValueError(
            "Configure model presets with /subagents; "
            "parent model environment is not inherited"
        )
    if options.thinking not in THINKING_LEVELS:
        raise ValueError("Invalid subagent thinkingLevel")


def validate_codex_handoff(options, agent_source):
    provider = options.model.split("/", 1)[0]
    options.codex_host = provider == CODEX_HOST
    if options.run and options.codex_handoff != options.codex_host:
        raise ValueError("Queued Codex handoff does not match the preset")
    if not options.codex_host:
        return
    # The stock parent wrapper exports this exact capability. Never resolve a
    # socket from XDG_RUNTIME_DIR, the profile, a preset, or a user CLI path.
    if (
        os.environ.get(CODEX_SOCKET_ENV) != str(CODEX_SOCKET)
        or CODEX_SOCKET.resolve() != CODEX_SOCKET
        or not CODEX_SOCKET.is_socket()
    ):
        raise ValueError(
            "codex-host requires the broker socket from the parent Pi wrapper"
        )
    if not extension_path(agent_source, CODEX_HOST).is_file():
        raise ValueError("Run pi-update: the codex-host extension is missing")
    project = Path(options.project_path)
    if agent_source.resolve(strict=True) != agent_source or any(
        project.is_relative_to(path) or path.is_relative_to(project)
        for path in (agent_source, Path.home() / ".pi")
    ):
        raise ValueError("Pi resources and the project mount must be separate")
    # The child will cover this file, never follow a link to another mount.
    default = agent_source / "codex-route-default"
    try:
        mode = default.lstat().st_mode
    except FileNotFoundError:
        pass
    else:
        if not stat.S_ISREG(mode):
            raise ValueError("codex-route-default must be a regular file")


def nix_proxy_directory():
    # Reuse the parent's bind mount, never the host daemon at the same path.
    for entry in Path("/proc/self/mountinfo").read_text().splitlines():
        root, target, flags = entry.split()[3:6]
        if (target == NIX_DAEMON_DIR and root.endswith("/pi-nix-daemon")
                and "ro" in flags.split(",")):
            return Path(NIX_DAEMON_DIR)
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise ValueError("XDG_RUNTIME_DIR is not set")
    return Path(runtime) / "pi-nix-daemon"


def sandbox_command(options, state, agent_source):
    home = Path.home()
    pi_home = home / ".pi"
    nix_proxy_dir = nix_proxy_directory()
    nix_proxy_socket = nix_proxy_dir / "socket"
    if not nix_proxy_socket.is_socket():
        raise ValueError(f"Nix proxy socket not found: {nix_proxy_socket}")
    bwrap: list[str | list[str]] = [
        "--unshare-all",
        "--share-net",
        "--die-with-parent",
        "--new-session",
        ["--dev", "/dev"],
        ["--proc", "/proc"],
        ["--tmpfs", "/nix"],
        ["--ro-bind", "/nix/store", "/nix/store"],
        ["--ro-bind", str(nix_proxy_dir), NIX_DAEMON_DIR],
        ["--remount-ro", "/nix"],
        ["--tmpfs", "/run"],
        ["--dir", "/run/pi-subagent"],
        ["--dir", str(home)],
    ]
    unset = {
        "PUEUE_CONFIG_PATH", "PI_PUEUE_NOTIFY_DIR", "PI_SESSION_ID",
        "PI_SESSION_FILE", "PI_PROVIDER", "PI_MODEL", "PI_REASONING_LEVEL",
        CODEX_SOCKET_ENV,
    }
    unset.update(key for key in os.environ if key.startswith("PI_CODEX_"))
    if options.codex_host:
        unset.add("CODEX_HOME")
    for key in sorted(unset):
        bwrap.append(["--unsetenv", key])
    for entry in ("/etc", "/bin", "/usr"):
        bwrap.append(["--ro-bind", entry, entry])
    if pi_home.is_dir():
        bwrap.extend([
            ["--overlay-src", str(pi_home), "--tmp-overlay", str(pi_home)],
            ["--tmpfs", str(pi_home / "agent/sessions")],
        ])
    if not agent_source.is_relative_to(pi_home):
        bwrap.append([
            "--overlay-src", str(agent_source),
            "--tmp-overlay", str(agent_source),
        ])
    if agent_source != pi_home / "agent":
        bwrap.append(["--tmpfs", str(agent_source / "sessions")])
    bwrap.extend([
        ["--bind", options.directory, options.project_path],
        ["--bind", str(state / "tmp"), "/tmp"],
        ["--bind", str(state / "sessions"), "/run/pi-subagent/sessions"],
        ["--ro-bind", str(state / "prompt.md"), "/run/pi-subagent/prompt.md"],
        ["--bind", str(state / "response.md"), "/run/pi-subagent/response.md"],
    ])
    # Match the parent's UPKI setup; the host remains the only cache writer.
    upki_config = Path("/etc/upki/config.toml")
    upki_cache = Path("/var/cache/upki")
    if upki_config.is_file():
        with upki_config.open("rb") as stream:
            upki_cache = Path(tomllib.load(stream)["cache-dir"])
    if upki_cache.is_dir():
        bwrap.append(["--ro-bind", str(upki_cache), str(upki_cache)])
    environment = {
        "HOME": str(home),
        "PWD": options.project_path,
        "TMPDIR": "/tmp",
        "PI_SUBAGENT_ROLE": "child",
        "PI_CODING_AGENT_DIR": str(agent_source),
        "PI_CODING_AGENT_SESSION_DIR": "/run/pi-subagent/sessions",
        "PI_SKIP_VERSION_CHECK": "1",
        "NIX_REMOTE": "daemon",
    }
    if options.codex_host:
        environment[CODEX_SOCKET_ENV] = str(CODEX_SOCKET)
        bwrap.append(["--ro-bind", str(CODEX_SOCKET), str(CODEX_SOCKET)])
        # stdin is /dev/null in run_child: cover the global route with an
        # empty regular file without reading or modifying the parent default.
        bwrap.append([
            "--ro-bind-data", "0", str(agent_source / "codex-route-default"),
        ])
    for key, value in environment.items():
        bwrap.append(["--setenv", key, value])
    instructions = CHILD_INSTRUCTIONS
    if options.no_inherit_resources:
        instructions += (
            "\nAutomatic extension and skill loading "
            "is disabled for this run.\n"
            "Only the pinned Pueue core and subagent adapter"
            + (" and host Codex provider" if options.codex_host else "")
            + " are explicitly loaded.\n"
        )
    if options.codex_host:
        instructions += (
            "\nHost Codex uses the parent's broker socket, not its login or "
            "route. New sessions use the broker's default routing; resumed "
            "sessions can retain their own route choice.\n"
        )
    if options.context:
        instructions += "\n## Additional context\n\n" + options.context + "\n"
    bwrap.append(["--chdir", options.project_path])
    command = [
        SUBAGENT_RUNNER,
        "/run/pi-subagent/prompt.md",
        "--",
        "--session-dir", "/run/pi-subagent/sessions",
        "--session-id", options.session_id,
        "--name", options.name,
        "--approve",
        "--append-system-prompt", instructions,
    ]
    if options.no_inherit_resources:
        command.extend(["--no-extensions", "--no-skills"])
    # Pi deduplicates discovered and explicit extensions by canonical path.
    names = PINNED_EXTENSIONS + ((CODEX_HOST,) if options.codex_host else ())
    for name in names:
        path = extension_path(agent_source, name)
        command.extend(["--extension", str(path)])
    if options.codex_host:
        command.extend(["--provider", CODEX_HOST])
    command.extend(["--model", options.model])
    if options.thinking:
        command.extend(["--thinking", options.thinking])
    bwrap_args = [
        arg for group in bwrap
        for arg in ([group] if isinstance(group, str) else group)
    ]
    return ["bwrap", *bwrap_args, "--", *command]


def run_child(options, state, agent_source):
    os.set_blocking(sys.stdout.fileno(), True)
    with lock(state, "execution.lock"):
        with (state / "stdout.log").open("wb") as output:
            with subprocess.Popen(
                sandbox_command(options, state, agent_source),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                bufsize=0,
            ) as process:
                assert process.stdout is not None
                while chunk := process.stdout.read(65536):
                    output.write(chunk)
                    output.flush()
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()
                returncode = process.wait()
        print(f"Report: {state / 'response.md'}", flush=True)
        print(f"Output: {state / 'stdout.log'}", flush=True)
        if returncode == 0:
            command = [
                "pi-subagent",
                options.name,
                options.directory,
                "/path/to/follow-up.md",
                "--resume",
                options.session_id,
            ]
            if options.context:
                command.append(f"--context={options.context}")
            if options.no_inherit_resources:
                command.append("--no-inherit-resources")
            print(f"Resume: {shlex.join(command)}", flush=True)
        return returncode


def parser():
    cli = argparse.ArgumentParser(prog="pi-subagent", description=__doc__)
    cli.add_argument("name", help="Human-readable task label")
    cli.add_argument("directory", help="Caller-prepared workspace")
    cli.add_argument("prompt_file", help="Task prompt file")
    cli.add_argument("--resume", help="Native Pi session ID to resume")
    cli.add_argument(
        "--profile", help="Named preset configured with /subagents"
    )
    cli.add_argument(
        "-c",
        "--context",
        help="Additional system context, such as a worker role",
    )
    cli.add_argument(
        "--no-inherit-resources",
        action="store_true",
        help="Skip extension/skill discovery; keep Pueue and preset Codex",
    )
    internal = cli.add_argument_group("internal arguments")
    internal.add_argument(
        "--run",
        action="store_true",
        help="Internal Pueue worker mode; do not invoke directly",
    )
    internal.add_argument(
        "--codex-handoff", action="store_true", help=argparse.SUPPRESS,
    )
    return cli


def main():
    options = parser().parse_args()
    if options.codex_handoff and not options.run:
        raise ValueError("--codex-handoff is only for queued workers")
    os.umask(0o077)
    options.directory = str(Path(options.directory).resolve(strict=True))
    if not Path(options.directory).is_dir():
        raise ValueError("Supply a workspace directory")
    options.project_path = os.getcwd()
    project = Path(options.project_path)
    if project in (Path("/"), Path.home()) or any(
        project == Path(prefix) or Path(prefix) in project.parents
        for prefix in (
            "/nix",
            "/run",
            "/tmp",
            "/proc",
            "/dev",
            "/etc",
            "/bin",
            "/usr",
        )
    ):
        raise ValueError("Project path overlaps a sandbox runtime mount")
    if not options.name.strip():
        raise ValueError("Name must not be empty")
    options.session_id = options.resume or str(uuid.uuid4())
    if not re.fullmatch(
        r"[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?", options.session_id
    ):
        raise ValueError("Invalid Pi session ID")
    state = STATE_ROOT / options.session_id
    workspace = Path(options.directory)
    if (
        workspace == STATE_ROOT
        or workspace.is_relative_to(STATE_ROOT)
        or STATE_ROOT.is_relative_to(workspace)
    ):
        raise ValueError("Workspace and session state must be separate")
    agent_dir = os.environ.get("PI_CODING_AGENT_DIR")
    if not agent_dir:
        raise ValueError(
            "PI_CODING_AGENT_DIR is required for subagent configuration"
        )
    agent_source = Path(agent_dir).absolute()
    for name in PINNED_EXTENSIONS:
        if not extension_path(agent_source, name).is_file():
            raise ValueError("Run pi-update before launching subagents")
    defaults(options, state, agent_source)
    validate_codex_handoff(options, agent_source)
    if options.run:
        return run_child(options, state, agent_source)
    prompt = Path(options.prompt_file).read_text()
    if not prompt.strip():
        raise ValueError("Prompt file must not be empty")
    if options.resume and not any(
        (state / "sessions").glob(f"*_{options.session_id}.jsonl")
    ):
        raise ValueError("Saved Pi session not found in this state directory")
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    with lock(state, "control.lock"):
        ensure_idle(state, options.session_id)
        for entry in ("sessions", "tmp"):
            (state / entry).mkdir(exist_ok=True, mode=0o700)
        (state / "selection.json").write_text(json.dumps({
            "model": options.model,
            "thinkingLevel": options.thinking,
        }) + "\n")
        (state / "prompt.md").write_text(prompt)
        (state / "response.md").write_text("")
        (state / "stdout.log").write_text("")
        group = subprocess.run(
            ["pueue", "group", "add", "--parallel", "4", "subagent"],
            capture_output=True,
            text=True,
        )
        if group.returncode and "already exists" not in group.stderr:
            raise ValueError(group.stderr.strip())
        command = [
            "pi-subagent",
            options.name,
            options.directory,
            str(state / "prompt.md"),
            "--resume",
            options.session_id,
            "--run",
        ]
        if options.codex_host:
            command.append("--codex-handoff")
        if options.context:
            command.append(f"--context={options.context}")
        if options.no_inherit_resources:
            command.append("--no-inherit-resources")
        result = subprocess.run(
            [
                "pueue",
                "add",
                "--immediate",
                "--group",
                "subagent",
                "--label",
                f"subagent:{options.session_id}:{options.name}",
                "--working-directory",
                options.project_path,
                "--print-task-id",
                "--escape",
                "--",
                *command,
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        print(
            json.dumps(
                {
                    "name": options.name,
                    "session_id": options.session_id,
                    "task_id": int(result.stdout.strip()),
                    "model": options.model,
                    "thinking_level": options.thinking,
                    "state_directory": str(state),
                    "response_path": str(state / "response.md"),
                    "stdout_path": str(state / "stdout.log"),
                },
                indent=2,
            )
        )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"pi-subagent: {error}", file=sys.stderr)
        sys.exit(1)
