"""Launch named Pi tasks with native sessions and supplied workspaces."""

import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import uuid

THINKING_LEVELS = ("off", "minimal", "low", "medium", "high", "xhigh", "max")
STATE_ROOT = Path("/tmp/pi-subagent-state")
PUEUE_CONFIG = """shared:
  pueue_directory: /run/pi-pueue
  runtime_directory: /run/pi-pueue
  use_unix_socket: true
  unix_socket_path: /run/pi-pueue/pueue.socket
  pid_path: /run/pi-pueue/pueue.pid
"""
CHILD_INSTRUCTIONS = """You are a subagent of the parent Pi agent.
Your working directory is a caller-prepared, possibly incomplete workspace
mounted at the original project path. The original project is not accessible.
The workspace can change between turns: reread relevant files before editing.
You inherit the parent's environment, tools, and skills. Your supplied project
is trusted by default.
Your ~/.pi resources are writable tmpfs overlays: changes there are discarded
when this process exits and never propagate to the parent. Symlink targets in
the Nix store remain immutable; replace the link with a copy if you need edits.
Nix store/daemon and networking are available.
Your Pueue daemon is private to this sandbox.
Your conversation is saved separately in /run/pi-subagent/sessions.
Write your report to /run/pi-subagent/response.md before ending the turn.
The parent reads that file, not your ordinary final message. Include concise
results, test outcomes, and changed files using project-relative paths.
If inputs are missing, report exactly what the parent should provide before
resuming you. Do not invoke or create other subagents.
"""


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


def defaults(options, agent_source):
    config_path = agent_source / "subagents.json"
    config = (
        json.loads(config_path.read_text()) if config_path.exists() else {}
    )
    if not isinstance(config, dict):
        raise ValueError(f"{config_path}: expected an object")
    model = config.get("model")
    thinking = config.get("thinkingLevel")
    if model is not None and not isinstance(model, str):
        raise ValueError(f"{config_path}: expected a model string or null")
    if thinking is not None and thinking not in THINKING_LEVELS:
        raise ValueError(f"{config_path}: invalid thinkingLevel")
    parent_model = None
    if os.environ.get("PI_MODEL") and os.environ.get("PI_PROVIDER"):
        parent_model = f"{os.environ['PI_PROVIDER']}/{os.environ['PI_MODEL']}"
    options.model = options.model or model or parent_model
    options.thinking = (
        options.thinking or thinking or os.environ.get("PI_REASONING_LEVEL")
    )


def sandbox_command(options, state, agent_source):
    home = Path.home()
    pi_home = home / ".pi"
    args = [
        "bwrap",
        "--unshare-all",
        "--share-net",
        "--die-with-parent",
        "--new-session",
        "--dev",
        "/dev",
        "--proc",
        "/proc",
        "--ro-bind",
        "/nix/store",
        "/nix/store",
        "--tmpfs",
        "/run",
        "--dir",
        "/run/pi-subagent",
        "--dir",
        "/run/pi-pueue",
        "--dir",
        str(home),
    ]
    for entry in ("/etc", "/bin", "/usr"):
        args.extend(["--ro-bind", entry, entry])
    if pi_home.is_dir():
        args.extend(
            [
                "--overlay-src",
                str(pi_home),
                "--tmp-overlay",
                str(pi_home),
                "--tmpfs",
                str(pi_home / "agent/sessions"),
            ]
        )
    if not agent_source.is_relative_to(pi_home):
        args.extend(
            [
                "--overlay-src",
                str(agent_source),
                "--tmp-overlay",
                str(agent_source),
            ]
        )
    if agent_source != pi_home / "agent":
        args.extend(["--tmpfs", str(agent_source / "sessions")])
    args.extend(
        [
            "--bind",
            options.directory,
            options.project_path,
            "--bind",
            str(state / "tmp"),
            "/tmp",
            "--bind",
            str(state / "sessions"),
            "/run/pi-subagent/sessions",
            "--ro-bind",
            str(state / "prompt.md"),
            "/run/pi-subagent/prompt.md",
            "--ro-bind",
            str(state / "pueue.yml"),
            "/run/pi-subagent/pueue.yml",
            "--bind",
            str(state / "response.md"),
            "/run/pi-subagent/response.md",
            "--ro-bind",
            "/nix/var/nix/daemon-socket",
            "/nix/var/nix/daemon-socket",
        ]
    )
    environment = {
        "HOME": str(home),
        "PWD": options.project_path,
        "TMPDIR": "/tmp",
        "PI_SUBAGENT_ROLE": "child",
        "PI_CODING_AGENT_DIR": str(agent_source),
        "PI_CODING_AGENT_SESSION_DIR": "/run/pi-subagent/sessions",
        "PUEUE_CONFIG_PATH": "/run/pi-subagent/pueue.yml",
        "PI_SKIP_VERSION_CHECK": "1",
        "NIX_REMOTE": "daemon",
    }
    for key, value in environment.items():
        args.extend(["--setenv", key, value])
    instructions = CHILD_INSTRUCTIONS
    if options.context:
        instructions += "\n## Additional context\n\n" + options.context + "\n"
    args.extend(
        [
            "--chdir",
            options.project_path,
            "--",
            "bash",
            "-c",
            'pueued -d && exec pi "$@"',
            "subagent-launch",
            "--print",
            "--session-dir",
            "/run/pi-subagent/sessions",
            "--session-id",
            options.session_id,
            "--name",
            options.name,
            "--approve",
            "--append-system-prompt",
            instructions,
        ]
    )
    if options.model:
        args.extend(["--model", options.model])
    if options.thinking:
        args.extend(["--thinking", options.thinking])
    args.append("@/run/pi-subagent/prompt.md")
    return args


def run_child(options, state, agent_source):
    with lock(state, "execution.lock"):
        with (state / "stdout.log").open("w") as output:
            result = subprocess.run(
                sandbox_command(options, state, agent_source),
                stdin=subprocess.DEVNULL,
                stdout=output,
                stderr=subprocess.STDOUT,
            )
        print(f"Report: {state / 'response.md'}", flush=True)
        print(f"Output: {state / 'stdout.log'}", flush=True)
        if result.returncode == 0:
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
            print(f"Resume: {shlex.join(command)}", flush=True)
        return result.returncode


def parser():
    cli = argparse.ArgumentParser(prog="pi-subagent", description=__doc__)
    cli.add_argument("name", help="Human-readable task label")
    cli.add_argument("directory", help="Caller-prepared workspace")
    cli.add_argument("prompt_file", help="Task prompt file")
    cli.add_argument("--resume", help="Native Pi session ID to resume")
    cli.add_argument("--model")
    cli.add_argument("--thinking", choices=THINKING_LEVELS)
    cli.add_argument(
        "-c",
        "--context",
        help="Additional system context, such as a worker role",
    )
    internal = cli.add_argument_group("internal arguments")
    internal.add_argument(
        "--run",
        action="store_true",
        help="Internal Pueue worker mode; do not invoke directly",
    )
    return cli


def main():
    options = parser().parse_args()
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
    agent_source = Path(
        os.environ.get("PI_CODING_AGENT_DIR", str(Path.home() / ".pi/agent"))
    ).absolute()
    if options.run:
        return run_child(options, state, agent_source)
    prompt = Path(options.prompt_file).read_text()
    if not prompt.strip():
        raise ValueError("Prompt file must not be empty")
    defaults(options, agent_source)
    if options.resume and not any(
        (state / "sessions").glob(f"*_{options.session_id}.jsonl")
    ):
        raise ValueError("Saved Pi session not found in this state directory")
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    with lock(state, "control.lock"):
        ensure_idle(state, options.session_id)
        for entry in ("sessions", "tmp"):
            (state / entry).mkdir(exist_ok=True, mode=0o700)
        (state / "prompt.md").write_text(prompt)
        (state / "pueue.yml").write_text(PUEUE_CONFIG)
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
            sys.executable,
            str(Path(__file__).resolve()),
            options.name,
            options.directory,
            str(state / "prompt.md"),
            "--resume",
            options.session_id,
            "--run",
        ]
        if options.model:
            command.extend(["--model", options.model])
        if options.thinking:
            command.extend(["--thinking", options.thinking])
        if options.context:
            command.append(f"--context={options.context}")
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
