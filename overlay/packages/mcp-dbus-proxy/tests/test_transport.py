import os
import pwd
import shutil
import subprocess
import sys
from pathlib import Path


def test_filtered_transport(tmp_path):
    runner = shutil.which("dbus-run-session")
    assert runner and shutil.which("xdg-dbus-proxy")
    command = [runner]
    config = Path(runner).resolve().parent.parent / "share/dbus-1/session.conf"
    if config.exists():
        command += [f"--config-file={config}"]
    command += ["--", sys.executable, str(Path(__file__).with_name("roundtrip.py"))]
    env = dict(os.environ)
    try:
        pwd.getpwuid(os.getuid())
    except KeyError:
        passwd, group = tmp_path / "passwd", tmp_path / "group"
        passwd.write_text(f"test:x:{os.getuid()}:{os.getgid()}:test:/tmp:/bin/sh\n")
        group.write_text(f"test:x:{os.getgid()}:\n")
        env.update(NSS_WRAPPER_PASSWD=str(passwd), NSS_WRAPPER_GROUP=str(group))
        env["LD_PRELOAD"] = env["MCP_TEST_NSS_WRAPPER"]
    subprocess.run(command, check=True, env=env, timeout=60)
