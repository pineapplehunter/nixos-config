import asyncio
import os
import signal
import sys
from contextlib import suppress
from pathlib import Path

from mcp_dbus_proxy import MAX_MESSAGE_BYTES
from mcp_dbus_proxy.host import Session


def test_noisy_backend_cleanup():
    async def check():
        process = await asyncio.create_subprocess_exec(
            sys.executable,
            "-c",
            "import os\nwhile True: os.write(1, b'x' * 65535 + b'\\n')",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            start_new_session=True,
            limit=MAX_MESSAGE_BYTES + 1,
        )
        session = Session("test", process)
        try:
            async with asyncio.timeout(5):
                while not process.stdout._paused:
                    await asyncio.sleep(0.01)
            await asyncio.wait_for(session.close(), 5)
            assert process.returncode is not None
        finally:
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)

    asyncio.run(check())


def test_descendant_cleanup_after_leader_exits(tmp_path):
    async def check():
        child_file = tmp_path / "child"
        program = (
            "import os, signal, sys, time\n"
            "from pathlib import Path\n"
            "if os.fork() == 0:\n"
            "    signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
            "    os.close(1)\n"
            "    Path(sys.argv[1]).write_text(str(os.getpid()))\n"
            "time.sleep(30)\n"
        )
        process = await asyncio.create_subprocess_exec(
            sys.executable,
            "-c",
            program,
            str(child_file),
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            start_new_session=True,
        )
        session = Session("test", process)
        try:
            async with asyncio.timeout(5):
                while not child_file.exists():
                    await asyncio.sleep(0.01)
                child = int(child_file.read_text())
                await session.close()
                while True:
                    try:
                        state = Path(f"/proc/{child}/stat").read_text().split()[2]
                    except FileNotFoundError:
                        break
                    if state == "Z":  # Exited; its new parent will reap it.
                        break
                    await asyncio.sleep(0.01)
        finally:
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)

    asyncio.run(check())
