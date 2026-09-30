"""Publish a sandbox-local Pueue completion without a live listener."""

import argparse
import json
import os
from pathlib import Path
import tempfile


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--id", type=int, required=True)
    options = cli.parse_args()
    if options.id < 0:
        cli.error("task ID must be nonnegative")
    directory = Path(os.environ.get("PI_PUEUE_NOTIFY_DIR", "/run/pi-pueue"))
    inbox = directory / "completions"
    inbox.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary = tempfile.mkstemp(prefix=".", dir=inbox)
    try:
        with os.fdopen(descriptor, "w") as output:
            json.dump({"task_id": options.id}, output)
        destination = inbox / f"event-{Path(temporary).name[1:]}.json"
        os.replace(temporary, destination)
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    main()
