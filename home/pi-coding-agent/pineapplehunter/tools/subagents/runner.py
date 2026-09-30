"""Run child Pi until its Pueue completion extension requests shutdown."""

import json
from pathlib import Path
import signal
import subprocess
import sys


def main():
    prompt = Path(sys.argv[1]).read_text()
    arguments = sys.argv[2:]
    if arguments and arguments[0] == "--":
        arguments = arguments[1:]
    process = subprocess.Popen(
        ["pi", "--mode", "rpc", *arguments],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
    )
    assert process.stdin is not None
    assert process.stdout is not None
    completed = False
    failure = None
    prompted = False

    def terminate(_signal, _frame):
        process.terminate()
        raise KeyboardInterrupt

    previous_handlers = {
        sig: signal.signal(sig, terminate)
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)
    }

    def send(record):
        process.stdin.write(json.dumps(record).encode("utf-8") + b"\n")
        process.stdin.flush()

    try:
        # Refuse to run without the lifecycle extension; otherwise RPC would
        # remain idle forever after the initial prompt.
        send({"id": "bootstrap", "type": "get_commands"})
        for line in process.stdout:
            sys.stdout.buffer.write(line)
            sys.stdout.buffer.flush()
            record = json.loads(line)
            if record.get("type") == "response":
                if not record.get("success"):
                    failure = record.get("error", "RPC command failed")
                    break
                if record.get("id") == "bootstrap":
                    commands = record.get("data", {}).get("commands", [])
                    if not any(
                        command.get("name") == "pueue-notifications"
                        for command in commands
                    ):
                        failure = "Pueue completion extension is not loaded"
                        break
                    send({
                        "id": "initial", "type": "prompt", "message": prompt,
                    })
                    prompted = True
            elif record.get("type") == "extension_error":
                failure = record.get("error", "Pi extension failed")
                break
            elif record.get("type") == "entry_appended":
                entry = record.get("entry", {})
                if entry.get("customType") == "pueue-subagent-exit":
                    completed = entry.get("data", {}).get("success") is True
                    failure = entry.get("data", {}).get("error")
                    if not completed:
                        failure = failure or "Completion processing failed"
                        break
            elif record.get("type") == "extension_ui_request":
                # Notifications need no response. Unattended children cannot
                # answer dialogs; cancel them rather than hanging the runner.
                if record.get("method") in (
                    "select", "confirm", "input", "editor",
                ):
                    send({
                        "type": "extension_ui_response",
                        "id": record["id"],
                        "cancelled": True,
                    })
        if failure:
            print(f"pi-subagent-runner: {failure}", file=sys.stderr)
            return 1
        if not prompted or not completed:
            print(
                "pi-subagent-runner: Pi exited before all task completions "
                "were processed", file=sys.stderr,
            )
            return 1
        return process.wait()
    except KeyboardInterrupt:
        return 130
    finally:
        process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        for sig, handler in previous_handlers.items():
            signal.signal(sig, handler)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"pi-subagent-runner: {error}", file=sys.stderr)
        sys.exit(1)
