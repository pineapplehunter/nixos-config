# Pineapplehunter Pi package

This directory is a ready-to-load Pi package. Its static `package.json` uses
Pi's conventional resource discovery; no generated manifest or per-file Nix
mapping is needed.

```text
package.json
extensions/
  nix-bash.ts
  nix-search.ts
  open-file/index.ts        # with OPEN_FILE.md
  pueue-tool/index.ts       # with DESIGN.md
skills/                    # complete personal skill directories
tools/subagents/           # launcher/runner sources and SUBAGENTS.md
wrapper/                   # sandbox/helper sources
sandbox-instructions.md
```

Try this directory directly from the repository root:

```sh
pi -e ./home/pi-coding-agent/pineapplehunter
```

Home Manager registers a Nix-store copy of this directory in `piPackages`,
alongside the existing npm packages. The separate `anthropic-skills` package is
assembled by a small `runCommand` that copies its static manifest and the curated
skills from the pinned upstream input. Both packages include complete skill
scripts/assets and design documentation.

Adding an extension under `extensions/` or a complete skill under `skills/`
requires no Nix or manifest edits. Pi supplies the declared peer dependencies;
no npm dependencies or second copies of Pi are bundled. Resolve helper paths
relative to the loaded skill's `SKILL.md`, not an assumed home resource path.

The parent `default.nix` still builds Python executables, sandbox services, and
Pueue configuration from these sources. `/open-file` and automatic Pueue turns
require the corresponding sandbox/host runtime; installing resources alone does
not provide those services.

Notifications and Radicale are normal host-side MCP servers, not Pi extensions.
The shared [MCP D-Bus bridge](../../../overlay/packages/mcp-dbus-proxy/README.md)
keeps credentials on the host. All enabled `services.mcp-dbus.servers` endpoints
are granted exact sandbox bus methods and merged into all three Pi profiles by the
parent's `update-mcp.py`, preserving unrelated MCP entries. Activation treats
these agent-writable paths as untrusted: symlink files/directories are rejected
and updates use directory-relative atomic replacement. Every tool has direct
exposure, without an agent-side approval gate. Application authorization belongs
to the host backend. Restart Pi after Home Manager activation to replace old
sandbox rules. The notification tool is now `mcp__notifications__notify`.

The parent's `update-settings.py` replaces the managed package list while
preserving unrelated Pi settings. Home Manager's activation script references
the package store paths, keeping them alive with the generation. On activation,
Home Manager removes resource links owned by the previous generation; unmanaged
user/project resources remain untouched. Restart Pi or reload after activation.
Subagents inherit the same package paths through the read-only Nix store.
Optional `pi-subagent --no-inherit-resources` suppresses automatic extension and
skill loading while explicitly retaining the pinned Pueue completion extension;
package resolution, other settings, prompts, and themes are unchanged. See
[the launcher documentation](tools/subagents/SUBAGENTS.md).

## Codex Auto

Run `pi-auto` to enable the `codex-auto` provider and `/codex-auto-usage`.
Ordinary `pi` and `pi-work` do not load those features. `pi-auto` uses its own
`~/.pi/agent-auto` directory and separate `auth.json`, sharing configuration
and resources with the personal profile like `pi-work`. Its normal provider
registry does not inherit personal or work logins. Select a mirrored model with
`/model` or start, for example:

```sh
pi-auto --model codex-auto/gpt-6.1-sol
```

Log in to `openai-codex` separately using `pi` (personal) and `pi-work` (work).
Codex Auto explicitly accesses those original credential files at
`~/.pi/agent/auth.json` and `~/.pi/agent-work/auth.json` using Pi's locked OAuth
refresh; it does not duplicate credentials. These files remain accessible to Pi
and its extensions inside the sandbox, so this separates default logins, not
security privileges. It uses personal while more than 15% of its
5-hour allowance remains, then work; it uses a usage sample for up to five minutes
and returns to personal after a reset. Quota reports and the reserve are best effort:
long requests, the sampling interval, delayed accounting, and concurrent sessions
can cross the limit.
If personal usage cannot be checked, work is used instead. If work is unavailable,
the request fails rather than spending the personal reserve.

The status line displays both accounts and their reset countdowns, highlighting
the account used for the latest request. It refreshes both accounts every five
minutes while visible and repaints the countdown every minute. Routing reuses a
fresh sample and fetches a new one when it expires or a reset passes.
`/codex-auto-usage` reports details and absolute reset times;
`/codex-auto-usage refresh` refreshes them and `/codex-auto-usage reserve 20`
sets the reserve to 20%. The setting is shared in `~/.pi/agent/codex-auto.json`.
Codex Auto uses Pi's standard Codex transport; switching accounts can cause a
prompt-cache miss. The ordinary `/usage` remains unchanged for other providers.

The plugin owns model-catalog refreshes: `/model` refreshes Codex through the
personal account runtime and publishes the result under `codex-auto`. It does
not depend on `agent-auto` having a default `openai-codex` login. Pi's normal
catalog cache/freshness policy applies; the five-minute usage cache is separate.

## Run without a flake

Use `pi @noflake` (or `pi-work @noflake` / `pi-auto @noflake`) to use the current directory as
the sandbox root instead of searching ancestors for `flake.nix`. All other
sandbox mounts and restrictions remain unchanged. Choose the directory carefully:
its contents are writable inside the sandbox.

Wrapper flags go before Pi arguments, for example:

```sh
pi @noflake --print "Summarize the files in this directory"
```

`@noflake` can be combined with `@debug-shell`, `@allow`, and `@allow-rw`.
`@@` ends wrapper-flag parsing.

## Browse background work

Use `/pueue-logs` to select a task or `/pueue-logs <id>` to open one directly.
Finished tasks remain browsable until cleaned. A compact, themed task table
shows statuses and human labels, with the selected command in a separate preview.
The framed log viewer follows live output, supports arrows/Page Up/Page Down
scrolling, and uses `f` to switch auto-follow on/off. Escape returns to the task
list or closes it; Ctrl+C closes without cancelling work.

Subagents show readable assistant output, tool calls/results, and errors from
their recorded RPC stream. Press `v` for raw output. The viewer keeps the last
5,000 lines and does not insert logs into the agent's context. Child-private
Pueue queues are not browsed. See `extensions/pueue-tool/DESIGN.md` for limits.

Edit repository sources rather than immutable installed packages.
