# Pi host integration

Home Manager installs Pi, `pi-update`, Bubblewrap wrappers (`pi`, `pi-work`,
`pi-auto`), Pueue/Node sandbox tools, subagent launcher/runner, clipboard,
portal clients, and host MCP registrations. Host/runtime sources remain under
`pineapplehunter/wrapper/` and `pineapplehunter/tools/subagents/`.

Extensions, global skills, external package declarations, and shared agent
instructions now live in the separate
[pi-customizations](https://github.com/pineapplehunter/pi-customizations)
repository. This module no longer imports those resources into the Nix store,
writes a package list during activation, or manages the global `AGENTS.md`.
Project-specific `.pi/skills` stay in this repository.

## Migration / updating

1. Rebuild Home Manager/NixOS once to install the updater and new runtime paths.
2. Before launching Pi/subagents, seed the copied package:

   ```sh
   pi-update --local /absolute/path/to/pi-customizations
   ```

3. Commit/push the resource repository to its default GitHub location, then use:

   ```sh
   pi-update
   ```

Both modes update all configured global external packages. `--local` only
changes the customization source; it always copies and never edits that checkout.
`--repo URL`/`--branch NAME` (or `PI_CUSTOMIZATIONS_REPO`/`PI_CUSTOMIZATIONS_BRANCH`)
override the default `pineapplehunter/pi-customizations` `main` source.

The package snapshot lives at `~/.pi/customizations/package/`, already visible
through existing `~/.pi` sandbox/subagent mounts. The launcher explicitly loads
that snapshot's public `extensions/pueue-tool/index.ts` and private
`extensions/subagent-pueue/index.ts` adapter for every child, including with
`--no-inherit-resources`; run the updater before launching subagents. Host code changes still need a rebuild; resources
need only an update and Pi reload/restart. Pi itself remains Nix-managed:
`pi-update` invokes the unwrapped executable's `update --extensions`, not
`pi update` (which would request a self-update).

The updater preserves unrelated preferences/packages, authentication, sessions,
and MCP settings. It tracks owned package entries, retires the two old
Nix-store resource packages, and replaces only its own resource snapshot. Existing
linked profile settings follow the personal profile; independent settings are
merged and updated separately. A failed external update exits nonzero but may
leave some external packages already updated; retry after fixing the error.
Home Manager activation itself performs no customization/package network update.

See the resource repository README for portability, package ownership, licenses,
and vendored upstream maintenance. The host MCP merge still uses `update-mcp.py`
and remains independent of customization updates.

## Private Pueue lifecycle

The wrapper directly executes Pi; it does not start Pueue or install a static
Pueue configuration/callback. The public snapshot extension automatically owns
a fresh private daemon, config, callback, and temporary directory per interactive
or RPC Pi process. Print/JSON mode starts no daemon. It never attaches to an
inherited config or host queue, and sets `PUEUE_CONFIG_PATH` and
`PI_PUEUE_NOTIFY_DIR` for subsequent commands. Reload/new/resume/fork within the
same process preserve that daemon; quitting kills tasks/daemon and removes its
temporary directory. The unrelated host Pueue user service is unchanged.

Children clear both inherited environment variables before Pi starts. Their
private adapter owns subagent completion/formatting and settlement shutdown;
the runner requires both `/pueue-notifications` and `/subagent-pueue-status`
before submitting the prompt and validates `pueue-subagent-exit` success/error.

## Wrapper flags

Use `pi @noflake` (also `pi-work`/`pi-auto`) to sandbox the current directory
instead of finding an ancestor `flake.nix`. That directory is writable inside
the sandbox. Wrapper flags precede Pi arguments, for example:

```sh
pi @noflake --print "Summarize this directory"
```

Combine with `@debug-shell`, `@allow PATH` (read-only), or `@allow-rw PATH`.
`@@` ends wrapper flag parsing. `@dev` exposes the entire host `/dev` and mounts
`/sys` read-only for hardware discovery. Host device permissions still apply;
only enable it for trusted hardware/firmware work. Without it, the minimal
sandbox `/dev` remains unchanged.

## Sandbox `/etc` and TLS

The wrapper populates a private `/etc` with Bubblewrap `--file` copies, not host
`/etc` bind mounts:

- Generates minimal `passwd`, `group`, `nsswitch.conf` (`hosts: files dns`), and
  `host.conf`. Host systemd/mDNS NSS services are not available in the sandbox.
- Copies host `hosts`, `resolv.conf`, and `localtime`, plus files under `/etc/nix`.
  Copies dereference NixOS's `/etc/static` symlinks; that whole tree is not exposed.
- Copies only `/etc/ssl/certs/ca-certificates.crt`, preserving host-added CAs,
  and creates the usual NixOS/Fedora bundle aliases. The other contents of
  `/etc/ssl` and `/etc/pki` are not exposed. `gai.conf` is omitted (glibc defaults).

These are launch-time snapshots: restart Pi after host DNS, trust, timezone, or
Nix configuration changes. Sandbox edits to these copies do not change the host.

The sandbox PATH includes `curl-upki`. The wrapper copies `/etc/upki/config.toml`
when present and mounts its configured `cache-dir` read-only (default
`/var/cache/upki`). Only the host `upki-fetch.service` updates the revocation
cache; sandboxed curl reads it. Subagents inherit the copied `/etc` and get the
same read-only cache mount. This does not enable UPKI in Node, Git, or every
other TLS client. UPKI soft-fails when no revocation data exists, so a successful
HTTPS request alone is not proof that revocation checking is active. Missing
UPKI configuration or cache is silently skipped. Populate the cache on the host with:

```sh
sudo systemctl start upki-fetch.service
```

## Git identity, signing, and attribution

All three wrappers use a filtered Git configuration generated from the host's
Home Manager `programs.git.settings.user` identity. They sign commits
through the automatically activated `pi-git-signing.service` on the host.
Only `GitSign1.SignCommit` is exposed through the filtered D-Bus proxy; the
sandbox receives no SSH key files or SSH-agent socket. Nothing from `~/.ssh`
is mounted by default. Git uses an opaque `pi-host-signer` key selector that the
client ignores; key selection stays entirely on the host.

The configured SSH public signing key (`programs.git.signing.key`, currently
`~/.ssh/id_ed25519.pub`) is used only by the host signer and must have its private
half loaded in the host SSH agent.
The user service needs the host's `SSH_AUTH_SOCK` in its systemd environment.
If your desktop does not import it automatically, run on the host:

```sh
systemctl --user import-environment SSH_AUTH_SOCK
systemctl --user restart pi-git-signing.service
```

There are no Pi Git hooks or hook-path overrides. The agent must include
`Assisted-By: pi (<model>)` as the final nonempty message line itself. The repository's
`.pi/skills/commit-conventions/SKILL.md` describes this before-commit workflow.
Missing or malformed final attribution is rejected by the host signer with
the required format and instructions to correct the message and retry.
Repository hooks and custom `core.hooksPath` are untouched. The attribution is
the selected Pi model ID, not an independently verified upstream model behind
a router. Agents can read `PI_MODEL` to write the attribution, but neither the
signing client nor the host signer requires that environment variable.

The broker checks the final commit payload, requiring the host committer identity
and a final line matching `Assisted-By: pi \([^\s()]+\)` before automatically
signing in the SSH `git` namespace. Original authors are preserved for
cherry-picks/rebases. Missing or malformed attribution, unavailable keys, and
signing failures fail closed. Only payload bytes are sent over D-Bus; the signer
does not receive or verify a separate model name.
The broker does not execute repository hooks or accept commands, key paths, or
filenames from clients. Signature verification stays local with `ssh-keygen`.

This policy applies to broker-signed commits: writable Git repositories still
allow deliberately unsigned commits. Automatic signing grants the agent commit
signing authority under your identity, not proof of human review. Signed tags
and arbitrary SSH signing requests are not supported by this broker.

Rebuild Home Manager/NixOS and restart Pi to activate these changes; an already
running sandbox keeps its old configuration and D-Bus permissions.

## Checks

```sh
python3 -m unittest discover -s home/pi-coding-agent/tests -p 'test_update*.py'
nix flake check --no-build --all-systems
```

Wrapper D-Bus tests need `dbus-next` and an explicitly private `dbus-run-session`;
see `tests/test_wrapper_dbus.py` and `tests/test_git_signing.py`. Signing tests
also need Git and OpenSSH; they create a temporary private SSH agent and never
use host keys or the desktop bus. They cover a signed commit and rejection of
an invalid message. For example, in a
Python environment with `dbus-next` installed:

```sh
PI_WRAPPER_TEST_PRIVATE_BUS=1 dbus-run-session -- \
  python3 -m unittest discover -s home/pi-coding-agent/tests -p 'test_git_signing.py'
```

Resource tests moved to pi-customizations.
