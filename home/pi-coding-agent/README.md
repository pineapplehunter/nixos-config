# Pi host integration

Home Manager installs the Bubblewrap-wrapped `pi`, `pi-update`,
Pueue/Node sandbox tools, subagent launcher/runner, clipboard,
portal clients, and host MCP registrations. Host/runtime sources remain under
`pineapplehunter/wrapper/` and `pineapplehunter/tools/subagents/`.

`default.nix` imports the sandbox and host daemon files, which together define
the Pi Home Manager module. `sandbox.nix` assembles the wrapper. The clipboard,
Git signing, GitHub fetch, Codex broker, and Nix proxy files define their own
services and activation files.

Extensions, global skills, external package declarations, and shared agent
instructions now live in the separate
[pi-customizations](https://github.com/pineapplehunter/pi-customizations)
repository. This module no longer imports those resources into the Nix store,
writes a package list during activation, or manages the global `AGENTS.md`.
Project-specific `.pi/skills` stay in this repository.

## Migration / updating

1. Rebuild Home Manager/NixOS once to install the updater and new runtime paths.
2. Before launching Pi or subagents, install the managed package:

   ```sh
   pi-update --local /absolute/path/to/pi-customizations
   ```

3. Commit/push the resource repository to its default GitHub location, then use:

   ```sh
   pi-update
   ```

Both modes pack the source and use `pi install` to install the tarball and its
runtime dependencies. `--local` includes uncommitted changes and never edits
or publishes the checkout. Without `--local`, the updater clones the configured
Git source. After installing, it updates all configured global external packages.
`--repo URL`/`--branch NAME` (or `PI_CUSTOMIZATIONS_REPO`/`PI_CUSTOMIZATIONS_BRANCH`)
override the default `pineapplehunter/pi-customizations` `main` source.

Pi installs the package at `~/.pi/agent/npm/node_modules/pi-customizations`.
The active tarball stays in `~/.pi/agent/pi-update/archives` for reinstalls.
Successful migration removes the old snapshot entry and deletes the old current
and previous snapshots, without touching unrelated files.

The launcher explicitly loads `extensions/pueue-tool/index.ts` and
`extensions/subagent-pueue/index.ts` from the active Pi profile’s installed
package, including with `--no-inherit-resources`. Run the updater before launching
subagents. Host code changes still need a rebuild; resources need only an update
and Pi reload/restart. Pi itself remains Nix-managed:
`pi-update` invokes the unwrapped executable's `update --extensions`, not
`pi update` (which would request a self-update).

The updater preserves unrelated preferences/packages, authentication, sessions,
and MCP settings. It tracks owned package entries, retires the two old
Nix-store resource packages, and installs only its own resource package. It
updates only `~/.pi/agent`. A failed external update exits nonzero but may leave
some packages already updated; retry after fixing the error.
Home Manager activation itself performs no customization/package network update.

See [Upstream sources and update notes](UPSTREAM.md) for the patched packages,
their exact release pins, and what to check before upgrading. The resource
repository README covers portability, package ownership, and vendored skills.
The host MCP merge still uses `update-mcp.py` and remains independent of
customization updates.

## Private Pueue lifecycle

The wrapper directly executes Pi; it does not start Pueue or install a static
Pueue configuration/callback. The public Pueue extension automatically owns
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

Use `pi @noflake` to sandbox the current directory
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

## Nix daemon access

Home Manager enables `pi-nix-daemon.socket` in the user manager's
`sockets.target`. The proxy listens at `$XDG_RUNTIME_DIR/pi-nix-daemon/socket`
and treats Pi clients as untrusted before forwarding requests to the host's
Nix daemon. Pi and its subagents see the proxy at the standard `/nix/var/nix/daemon-socket/socket`
path without changing their Nix configuration. They mount `/nix/store`
read-only and do not mount the host daemon socket or Nix state directory.

Pi and its subagents refuse to start if the proxy socket is missing. Start it
on the host with `systemctl --user start pi-nix-daemon.socket` if needed.
After activation, restart running Pi sessions. Inside Pi,
`nix store info --json` should report `"trusted": false`.

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

## Host Codex chat

The Linux Pi wrapper enables the socket-activated broker and installs the
host-only `pi-codex-auth` command by default. Set
`programs.pi-coding-agent.codexHost.enable = false;` to opt out.
After applying Home Manager, run in a **host terminal**:

```sh
systemctl --user start pi-codex-host.socket
pi-codex-auth login work
pi-codex-auth status
pi-update --local /path/to/pi-customizations
```

Start a fresh `pi` and choose a model under **Codex (host)**
in `/model`. Run `pi-codex-auth` on the host to manage the account logins and
Auto reserve. Log in to Personal separately with `pi-codex-auth login personal`.
The reserve defaults to 15%.

Choose Personal, Work, or Auto in `/codex-route`. Enter changes just the
current session and is restored on resume. Ctrl+S also saves the highlighted
route as the default for sessions without an explicit choice. To set a
default model, use Ctrl+S separately in `/model`.

Auto is offered when both logins are configured. It uses Personal only
while its five-hour allowance is above the reserve, otherwise it tries
Work. If Work is unavailable it won't dip into the reserve. A Personal
quota error can switch to Work only before the response starts. The
providers refresh the host's public Codex catalog at startup and through
Pi's model refresh, so newly published
models are not limited to the catalog bundled with Pi. Offline startup uses
the broker's current catalog; a failed refresh retains it and reports a warning.
After rebuilding broker code, restart `pi-codex-host.service` on the host,
update customizations, and restart Pi. Stop or restart the socket only from
the host.

Account credentials live under `~/.local/state/pi-codex-host/`, outside
the normal sandbox mounts. Do not expose that directory via a project mount,
portal, or wrapper allow flag. Only the broker's runtime socket directory
is mounted, read-only; the broker cannot execute tools or read the workspace.
Broker-enabled plain `pi` can run `codex-host/<model>` subagent presets,
including with `--no-inherit-resources`. Select one explicitly in `/subagents`;
the launcher does not rewrite presets or pass the parent's route to a new
child. See the [subagent guide](pineapplehunter/tools/subagents/SUBAGENTS.md).

Brokered `web_search` and `source_check` require the pinned `pi-web-access`
0.48.0 patch. See `extensions/codex-host/web/README.md` in pi-customizations
for activation and rollback. Hosted search follows `/codex-route` and does
not fall back to paid OpenAI. Independent search providers, page fetching,
and the GitHub shim are unchanged.

`/usage` and the footer show the active host Codex account. In Auto, send a
prompt first so the broker can report which account it used. `/usage` can
check and redeem earned reset credits after a Pi confirmation; the host
binds the selection to the displayed account and credit and does not retry
redemption.

`/fast` checks whether the current model and account support priority
requests before enabling them. It starts off and turns off when you
change model, route, or session. Auto checks support again on whichever
account it selects, including Work on fallback; it won't silently send a
standard request instead. Priority can use more quota.

## Codex image generation

With `codexHost` enabled, the Linux wrapper ships the broker-only
`pi-codex-image-gen` tools. In a host terminal,
open `pi-codex-auth` and choose **Work images** or **Personal images** to manage
sign-ins. **Set image route** selects which sign-in to use, or turns routing off.
You can also use:

```sh
pi-codex-auth image-login work
pi-codex-auth images work       # work (default), personal, or off
pi-codex-auth status
```

Image logins are separate from chat and stored under
`~/.local/state/pi-codex-host/images/`. The selected image account is
independent of the chat model or route. If it is unconfigured or Off, Pi
does not fall back to another account or a local login. Image files are read
and saved in the sandbox; the host
receives only the request and reference bytes.

## Authenticated GitHub fetching

The Linux Pi wrapper enables the GitHub broker by default. Set
`programs.pi-coding-agent.githubFetch.enable = false;` to opt out. For
authenticated reads, sign in with `gh auth login --hostname github.com` on
the host.

After switching Home Manager, restart Pi. The service uses the host's normal
`gh` authentication; the sandbox receives no credentials. The sandbox's
`gh` shim supports the GitHub reads used by `pi-web-access`'s `fetch_content`:
repo metadata, trees,
README and file content, issue/PR details, and PR review comments. The
filtered D-Bus proxy exposes one method. The host service checks the complete
argument list and invokes a fixed `gh` executable without a shell. It does not
offer general `gh api`, search, auth, or write commands.

Public shallow clones still use sandbox-local Git. Private repos are fetched
via the read API, not cloned with the host login. Any repo the host login can
read through these operations is readable by the agent. Do not mount the
host's GitHub CLI config directory into the sandbox.

## Git identity, signing, and attribution

The Pi wrapper uses a filtered Git configuration generated from the host's
Home Manager `programs.git.settings.user` identity. It signs commits through
the automatically activated `pi-git-signing.service` on the host.
Only `GitSign1.SignCommit` is exposed through the filtered D-Bus proxy; the
sandbox receives no SSH key files or SSH-agent socket. Nothing from `~/.ssh`
is mounted by default. Git uses an opaque `pi-host-signer` key selector that the
client ignores; key selection stays entirely on the host.

The configured SSH public signing key (`programs.git.signing.key`, set to
`${config.home.homeDirectory}/.ssh/id_ed25519.pub`) is passed as an absolute path
to the host signer and must have its private half loaded in the host SSH agent.
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
