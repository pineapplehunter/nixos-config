"""Offline launcher tests: no Pueue daemon, Pi process or account access."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import socket
from subprocess import CompletedProcess
import sys
import tempfile
import unittest
from unittest.mock import patch


class CodexHandoffTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(dir="/tmp")
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name).resolve()
        home = root / "home"
        self.agent = home / ".pi/agent"
        self.agent.mkdir(parents=True)
        self.workspace = root / "workspace"
        self.workspace.mkdir()
        self.prompt = root / "prompt.md"
        self.prompt.write_text("Synthetic prompt\n")
        self.default = self.agent / "codex-route-default"
        self.default.write_text("work\n")
        self.preset = self.agent / "subagents.json"
        self.preset.write_text(json.dumps({"model": "codex-host/fixture"}))
        broker = root / "broker.sock"
        listening = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.addCleanup(listening.close)
        listening.bind(str(broker))
        self.nix_socket = root / "runtime/pi-nix-daemon/socket"
        self.nix_socket.parent.mkdir(parents=True)
        nix_listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.addCleanup(nix_listener.close)
        nix_listener.bind(str(self.nix_socket))
        self.mountinfo = root / "mountinfo"
        self.mountinfo.touch()
        self.enterContext(patch.dict(os.environ, {
            "HOME": str(home),
            "XDG_RUNTIME_DIR": str(root / "runtime"),
            "PI_CODING_AGENT_DIR": str(self.agent),
            "PI_CODING_AGENT_SESSION_DIR": "/parent/sessions",
            "PI_CODEX_HOST_SOCKET": str(broker),
            "PI_CODEX_HOST_AUTH_FILE": "/not-mounted/host-only.json",
            "PI_CODEX_ROUTE": "work",
            "PI_SESSION_FILE": "/parent/transcript",
            "PI_SESSION_ID": "parent",
            "PI_PROVIDER": "something-else",
            "PI_MODEL": "parent-model",
            "PI_REASONING_LEVEL": "max",
            "CODEX_HOME": "/not-mounted/codex",
        }, clear=True))
        spec = importlib.util.spec_from_file_location(
            "launcher", Path(__file__).with_name("launcher.py"),
        )
        self.launcher = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.launcher)
        self.launcher.STATE_ROOT = root / "state"
        self.launcher.CODEX_SOCKET = broker
        for ext in (*self.launcher.PINNED_EXTENSIONS,
                    self.launcher.CODEX_EXTENSION):
            ext.parent.mkdir(parents=True, exist_ok=True)
            ext.touch()
        # Do not inspect the real UPKI config when constructing argv.
        path = self.enterContext(patch.object(
            self.launcher, "Path", side_effect=lambda value: (
                self.mountinfo if value == "/proc/self/mountinfo" else
                root / "no-upki" if str(value) in (
                    "/etc/upki/config.toml", "/var/cache/upki",
                ) else Path(value)
            ),
        ))
        path.home.return_value = home
        self.cli = ["pi-subagent", "fixture", str(self.workspace),
                    str(self.prompt)]
        self.enterContext(patch.object(os, "getcwd", return_value="/project"))
        self.enterContext(patch.object(os, "umask"))

    def options(self, *args):
        options = self.launcher.parser().parse_args([*self.cli[1:], *args])
        options.project_path = "/project"
        options.session_id = "child"
        self.launcher.defaults(options, self.launcher.STATE_ROOT, self.agent)
        return options

    def test_brokered_argv_both_resource_modes(self):
        for no_inherit in (False, True):
            with self.subTest(no_inherit=no_inherit):
                options = self.options()
                options.no_inherit_resources = no_inherit
                self.launcher.validate_codex_handoff(options, self.agent)
                args = self.launcher.sandbox_command(
                    options, self.launcher.STATE_ROOT, self.agent,
                )
                mounts = args[:args.index("--")]
                pi = args[args.index("--") + 1:]
                broker = str(self.launcher.CODEX_SOCKET)
                bind = mounts.index(broker)
                self.assertEqual(mounts[bind-1:bind+2],
                                 ["--ro-bind", broker, broker])
                mask = mounts.index("--ro-bind-data")
                self.assertEqual(mounts[mask+1:mask+3],
                                 ["0", str(self.default)])
                self.assertEqual(self.default.read_text(), "work\n")
                for key in ("PI_CODEX_HOST_AUTH_FILE", "PI_CODEX_ROUTE",
                            "PI_SESSION_FILE", "PI_SESSION_ID", "PI_MODEL",
                            "CODEX_HOME", "PI_CODEX_HOST_SOCKET"):
                    self.assertIn(("--unsetenv", key), zip(mounts, mounts[1:]))
                setenv = [(a, b) for flag, a, b in
                          zip(mounts, mounts[1:], mounts[2:])
                          if flag == "--setenv"]
                self.assertIn(("PI_CODEX_HOST_SOCKET", broker), setenv)
                self.assertIn(("NIX_REMOTE", "daemon"), setenv)
                nix_socket = mounts.index("/nix/var/nix/daemon-socket")
                self.assertEqual(mounts[nix_socket-2:nix_socket], [
                    "--ro-bind", str(self.nix_socket.parent),
                ])
                self.assertIn(("PI_CODING_AGENT_SESSION_DIR",
                               "/run/pi-subagent/sessions"), setenv)
                self.assertFalse(any("/not-mounted/" in arg for arg in args))
                self.assertEqual(pi[pi.index("--provider") + 1], "codex-host")
                self.assertEqual(pi[pi.index("--model") + 1],
                                 "codex-host/fixture")
                self.assertEqual(pi[pi.index("--session-id") + 1], "child")
                self.assertEqual(no_inherit, "--no-extensions" in pi)
                self.assertEqual(no_inherit, "--no-skills" in pi)
                for ext in (*self.launcher.PINNED_EXTENSIONS,
                            self.launcher.CODEX_EXTENSION):
                    self.assertIn(("--extension", str(ext)), zip(pi, pi[1:]))

    def test_other_preset_does_not_get_socket_or_provider(self):
        self.preset.write_text('{"model":"openai-codex/fixture"}')
        options = self.options("--no-inherit-resources")
        self.launcher.validate_codex_handoff(options, self.agent)
        args = self.launcher.sandbox_command(
            options, self.launcher.STATE_ROOT, self.agent,
        )
        self.assertNotIn(str(self.launcher.CODEX_SOCKET), args)
        self.assertNotIn(str(self.launcher.CODEX_EXTENSION), args)
        self.assertNotIn(str(self.default), args)
        self.assertIn("openai-codex/fixture", args)

    def test_rebinds_parent_nix_proxy_at_standard_path(self):
        daemon_dir = str(self.nix_socket.parent)
        options = self.options()
        self.launcher.validate_codex_handoff(options, self.agent)
        self.mountinfo.write_text(f"2 1 0:1 /pi-nix-daemon {daemon_dir} ro\n")
        with (
            patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/not-mounted"}),
            patch.object(self.launcher, "NIX_DAEMON_DIR", daemon_dir),
        ):
            args = self.launcher.sandbox_command(
                options, self.launcher.STATE_ROOT, self.agent,
            )
        mount = args.index(daemon_dir)
        self.assertEqual(args[mount-1:mount+2],
                         ["--ro-bind", daemon_dir, daemon_dir])

    def test_missing_nix_proxy_prevents_launch(self):
        daemon_dir = self.launcher.NIX_DAEMON_DIR
        self.mountinfo.write_text(f"2 1 0:1 {daemon_dir} {daemon_dir} ro\n")
        self.nix_socket.unlink()
        with self.assertRaisesRegex(ValueError, "Nix proxy socket not found"):
            self.launcher.sandbox_command(
                self.options(), self.launcher.STATE_ROOT, self.agent,
            )

    def test_unauthorized_and_invalid_socket(self):
        options = self.options()
        broker = self.launcher.CODEX_SOCKET
        for socket_env in ("", str(broker.with_name("other.sock"))):
            with patch.dict(os.environ, {"PI_CODEX_HOST_SOCKET": socket_env}):
                with self.assertRaisesRegex(ValueError, "parent Pi wrapper"):
                    self.launcher.validate_codex_handoff(options, self.agent)
        # A real socket at the target of a symlink is still not acceptable.
        broker.rename(broker.with_name("moved.sock"))
        broker.symlink_to(broker.with_name("moved.sock"))
        with self.assertRaisesRegex(ValueError, "parent Pi wrapper"):
            self.launcher.validate_codex_handoff(options, self.agent)
        broker.unlink()
        broker.touch()
        with self.assertRaisesRegex(ValueError, "parent Pi wrapper"):
            self.launcher.validate_codex_handoff(options, self.agent)

    def test_invalid_layout(self):
        options = self.options()
        options.project_path = str(self.agent.parent)
        with self.assertRaisesRegex(ValueError, "must be separate"):
            self.launcher.validate_codex_handoff(options, self.agent)
        options.project_path = "/project"
        self.default.unlink()
        self.default.symlink_to(self.preset)
        with self.assertRaisesRegex(ValueError, "regular file"):
            self.launcher.validate_codex_handoff(options, self.agent)
        self.default.unlink()
        self.launcher.CODEX_EXTENSION.unlink()
        with self.assertRaisesRegex(ValueError, "Run pi-update"):
            self.launcher.validate_codex_handoff(options, self.agent)

    def test_queue_handoff_checked_again_in_worker(self):
        initial_preset = self.preset.read_bytes()
        with (
            patch.object(sys, "argv", [*self.cli, "--no-inherit-resources"]),
            contextlib.redirect_stdout(io.StringIO()) as output,
            patch.object(self.launcher.subprocess, "run", side_effect=[
                CompletedProcess([], 0, '{"tasks":{}}', ""),
                CompletedProcess([], 0, "", ""),
                CompletedProcess([], 0, "12", ""),
            ]) as pueue,
        ):
            self.assertEqual(self.launcher.main(), 0)
        result = json.loads(output.getvalue())
        queued = pueue.call_args.args[0]
        command = queued[queued.index("--") + 1:]
        self.assertIn("--codex-handoff", command)
        self.assertIn("--no-inherit-resources", command)
        self.assertNotIn(str(self.launcher.CODEX_SOCKET), command)
        selection = Path(result["state_directory"]) / "selection.json"
        self.assertEqual(json.loads(selection.read_text()), {
            "model": "codex-host/fixture", "thinkingLevel": "off",
        })
        self.assertEqual(self.preset.read_bytes(), initial_preset)
        with (
            patch.object(sys, "argv", command),
            patch.object(self.launcher, "run_child", return_value=0) as child,
        ):
            self.assertEqual(self.launcher.main(), 0)
            self.assertEqual(child.call_args.args[0].model, result["model"])
            child.reset_mock()
            with patch.dict(os.environ, {"PI_CODEX_HOST_SOCKET": ""}):
                with self.assertRaisesRegex(ValueError, "parent Pi wrapper"):
                    self.launcher.main()
            child.assert_not_called()
            command.remove("--codex-handoff")
            with self.assertRaisesRegex(ValueError, "handoff does not match"):
                self.launcher.main()
            child.assert_not_called()


if __name__ == "__main__":
    unittest.main()
