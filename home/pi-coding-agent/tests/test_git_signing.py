"""Run with PI_WRAPPER_TEST_PRIVATE_BUS=1 under dbus-run-session."""

import asyncio
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

from dbus_next import NameFlag
from dbus_next.aio import MessageBus

WRAPPER = Path(__file__).resolve().parents[1] / "pineapplehunter/wrapper"
sys.path.insert(0, str(WRAPPER))
import git_sign_daemon as daemon  # noqa: E402


class Signing(unittest.IsolatedAsyncioTestCase):
    async def command(self, *arguments, env=None):
        process = await asyncio.create_subprocess_exec(
            *map(str, arguments),
            env=env,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(process.communicate(), 10)
        return process.returncode, stdout.decode(), stderr.decode()

    async def git(self, *arguments, success=True):
        result = await self.command(
            "git", "-C", self.repo, *arguments, env=self.environment
        )
        if success:
            self.assertEqual(result[0], 0, result[2])
        else:
            self.assertNotEqual(result[0], 0, result)
        return result

    async def asyncSetUp(self):
        self.assertTrue(os.environ.get("PI_WRAPPER_TEST_PRIVATE_BUS"))
        self.temp = tempfile.TemporaryDirectory(prefix="pi-git-signing-test-")
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.key = self.root / "host-key"
        result = await self.command(
            "ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", self.key
        )
        self.assertEqual(result[0], 0, result)
        socket = self.root / "agent.sock"
        self.agent = await asyncio.create_subprocess_exec(
            "ssh-agent",
            "-D",
            "-a",
            str(socket),
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        async with asyncio.timeout(3):
            while not socket.is_socket():
                await asyncio.sleep(0.01)
        self.old_agent = os.environ.get("SSH_AUTH_SOCK")
        os.environ["SSH_AUTH_SOCK"] = str(socket)
        result = await self.command("ssh-add", self.key)
        self.assertEqual(result[0], 0, result)
        self.bus = await MessageBus().connect()
        self.bus.export(
            daemon.OBJECT_PATH,
            daemon.GitSigner(
                shutil.which("ssh-keygen"),
                str(self.key) + ".pub",
                "Host User",
                "host@example.invalid",
            ),
        )
        await self.bus.request_name(daemon.BUS_NAME, NameFlag.DO_NOT_QUEUE)
        signer = self.root / "pi-git-sign"
        signer.write_text(
            f"#!{sys.executable}\n"
            + (WRAPPER / "git_sign_client.py").read_text()
        )
        signer.chmod(0o755)
        config = self.root / "gitconfig"
        self.environment = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("GIT_", "SSH_AUTH_"))
        } | {
            "GIT_CONFIG_GLOBAL": str(config),
            "GIT_CONFIG_NOSYSTEM": "1",
        }
        await self.git("init", "-q")
        for key, value in {
            "user.name": "Host User",
            "user.email": "host@example.invalid",
            # Opaque selector, not a key file; key access stays on the host.
            "user.signingKey": "pi-host-signer",
            "gpg.format": "ssh",
            "gpg.ssh.program": str(signer),
            "commit.gpgSign": "true",
        }.items():
            await self.git("config", "--file", config, key, value)
        allowed = self.root / "allowed_signers"
        allowed.write_text(
            "host@example.invalid " + Path(str(self.key) + ".pub").read_text()
        )
        await self.git("config", "gpg.ssh.allowedSignersFile", allowed)

    async def asyncTearDown(self):
        self.bus.disconnect()
        await self.bus.wait_for_disconnect()
        self.agent.terminate()
        await asyncio.wait_for(self.agent.wait(), 3)
        if self.old_agent is None:
            os.environ.pop("SSH_AUTH_SOCK", None)
        else:
            os.environ["SSH_AUTH_SOCK"] = self.old_agent
        self.temp.cleanup()

    async def test_commit_is_created_and_signed(self):
        await self.git(
            "commit",
            "--allow-empty",
            "-m",
            "test: sign a commit\n\nAssisted-By: pi (test-model)",
        )
        await self.git("verify-commit", "HEAD")

    async def test_invalid_message_is_rejected(self):
        await self.git(
            "commit",
            "--allow-empty",
            "-m",
            "missing attribution",
            success=False,
        )
        await self.git("rev-parse", "--verify", "HEAD", success=False)


if __name__ == "__main__":
    unittest.main()
