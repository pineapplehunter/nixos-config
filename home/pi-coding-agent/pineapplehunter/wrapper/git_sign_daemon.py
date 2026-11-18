"""Host-side SSH commit signer; never accepts commands, paths, or keys."""

import argparse
import asyncio
from pathlib import Path
import re
import sys

from dbus_next import DBusError, NameFlag, RequestNameReply
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method

BUS_NAME = "io.github.pineapplehunter.GitSign1"
OBJECT_PATH = "/io/github/pineapplehunter/GitSign1"
MAX_PAYLOAD_BYTES = 1024 * 1024


def validate_commit(payload, name, email):
    if len(payload) > MAX_PAYLOAD_BYTES or b"\0" in payload:
        raise ValueError("commit payload is invalid or exceeds 1 MiB")
    headers, separator, message = payload.partition(b"\n\n")
    lines = headers.split(b"\n")
    if not separator or not re.fullmatch(
        rb"tree (?:[0-9a-f]{40}|[0-9a-f]{64})", lines[0]
    ):
        raise ValueError("only Git commit payloads can be signed")
    authors = [line for line in lines if line.startswith(b"author ")]
    committers = [line for line in lines if line.startswith(b"committer ")]
    expected = f"committer {name} <{email}>".encode()
    if (
        len(authors) != 1
        or len(committers) != 1
        or not re.fullmatch(
            re.escape(expected) + rb" -?[0-9]+ [+-][0-9]{4}", committers[0]
        )
        or any(line.startswith(b"gpgsig") for line in lines)
    ):
        raise ValueError("commit must use the host committer identity")
    last_line = message.rstrip(b"\n").rsplit(b"\n", 1)[-1]
    if not re.fullmatch(rb"Assisted-By: pi \([^\s()]+\)", last_line):
        raise ValueError(
            "Commit message is missing a valid final Pi attribution line. "
            "End your commit message with:\n\n"
            "Assisted-By: pi (<model>)\n\n"
            "Check the PI_MODEL environment variable for the current "
            "model name. Replace <model> with a nonempty model name without "
            "whitespace or parentheses, then retry git commit with the "
            "corrected message. The signer checks the format only, not the "
            "model's identity. No commit was created. Do not disable signing "
            "to bypass this requirement."
        )


class GitSigner(ServiceInterface):
    def __init__(self, ssh_keygen, key, name, email):
        super().__init__(BUS_NAME)
        self.ssh_keygen = ssh_keygen
        self.key = str(Path(key).expanduser())
        self.committer_name = name
        self.committer_email = email

    @method()
    async def SignCommit(  # noqa: F722
        self,
        payload: "ay",  # noqa: F821
    ) -> "ay":  # noqa: F821
        try:
            validate_commit(payload, self.committer_name, self.committer_email)
        except ValueError as error:
            raise DBusError(
                BUS_NAME + ".Error.InvalidCommit", str(error)
            ) from None
        process = None
        try:
            process = await asyncio.create_subprocess_exec(
                self.ssh_keygen,
                "-Y",
                "sign",
                "-n",
                "git",
                "-f",
                self.key,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            signature, stderr = await asyncio.wait_for(
                process.communicate(payload), 30
            )
            if process.returncode:
                raise DBusError(
                    BUS_NAME + ".Error.SignFailed",
                    stderr.decode(errors="replace").strip()
                    or "ssh-keygen failed",
                )
            return signature
        except (OSError, TimeoutError) as error:
            raise DBusError(
                BUS_NAME + ".Error.SignFailed", str(error)
            ) from None
        finally:
            if process is not None and process.returncode is None:
                process.kill()
                await process.wait()


async def serve(args):
    connection = MessageBus()
    try:
        await connection.connect()
        connection.export(
            OBJECT_PATH,
            GitSigner(args.ssh_keygen, args.key, args.name, args.email),
        )
        ownership = await connection.request_name(
            BUS_NAME, NameFlag.DO_NOT_QUEUE
        )
        if ownership != RequestNameReply.PRIMARY_OWNER:
            raise RuntimeError(f"could not own {BUS_NAME}: {ownership.name}")
        await connection.wait_for_disconnect()
    finally:
        connection.unexport(OBJECT_PATH)
        connected = connection.connected
        connection.disconnect()
        if connected:
            await connection.wait_for_disconnect()


def main():
    parser = argparse.ArgumentParser()
    for option in ("ssh-keygen", "key", "name", "email"):
        parser.add_argument("--" + option, required=True)
    args = parser.parse_args()
    try:
        asyncio.run(serve(args))
        return 0
    except (DBusError, OSError, RuntimeError) as error:
        print(f"pi-git-signingd: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
