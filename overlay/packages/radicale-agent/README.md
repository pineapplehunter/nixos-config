# Radicale Agent broker

A host-side CalDAV service and credential-free MCP stdio facade for sandboxed
agents. **Only the existing collection named `Agent`, pinned by exact URL, is
accessible.** No collection creation/deletion or Radicale server changes.

## Features and verification

- Discover the authorized collection and inspect `VEVENT` / `VTODO` support.
- List, read, create, partially update and delete non-recurring events.
- List, read, create, update, complete, reopen and delete non-recurring tasks.
- Due dates, priorities, completion percentages/status/timestamps, timezone-aware
  instants and all-day dates. Bounded recurrence expansion for event display.
- Host-side validation and allowlist; structured JSON; sanitized errors/audit
  metadata; conditional writes; stable UIDs and idempotent creates.
- Default read-only mode; a separate D-Bus Write method requires host opt-in.
- **File-only credentials**: username/password never come from environment
  variables. Only `CALDAV_CREDENTIALS_FILE` contains their path.

On 2026-10-16, **77 local tests and 7 live tests passed**. Live tests used the
user-approved existing Agent collection and verified actual event/task
create/read/update/complete round trips, all-day dates, task reopening,
recurrence expansion with an override, preservation of unknown properties,
categories/alarms, safe create/completion retries, and an actual HTTP If-Match
race against an independent client. They also called **all ten MCP tools** over
stdio through a private broker and the real filtered `xdg-dbus-proxy` to Radicale.
A deletion follow-up passed 89 local checks and four targeted live checks,
covering both delete tools, repeat deletion, stale ETags, an actual concurrent
DELETE conflict and all twelve MCP tools through the filtered bus. The new
fixtures were removed and independently verified absent.

The independent verification path uses HTTP + iCalendar, not the service's
adapter/normalizer. Desktop GUI display, interactive Inspector and systemd/D-Bus
activation on the deployed desktop have **not** been manually verified. All items
created for verification were subsequently deleted or confirmed already absent;
unrelated items were not modified. Future live test runs create new fixtures.

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for scope and design decisions.

## Architecture

```text
Pi sandbox / MCP client -> MCP stdio facade (no credentials)
  -> filtered session D-Bus Read / Write methods
  -> host CalendarService (validation, fixed collection policy)
  -> python-caldav + icalendar -> existing Radicale over verified HTTPS
```

The broker, not MCP schemas, enforces authorization. Collection ID must be
exactly `Agent`; the configured URL must match a discovered collection whose
display name is also `Agent`. Another collection with the same name is not
allowed. The agent cannot supply URLs or change credentials, scope or write mode.
Administrative discovery of all collections is a host-only CLI, not a tool.

## Home Manager + sops-nix setup

1. Identify the existing **Agent** collection supporting both components. If
   missing, create it yourself or explicitly approve creation. This package
   never creates collections or adjusts server rights.
2. With `sops`, add the key `radicale-agent-credentials` to your existing encrypted
   Home Manager SOPS YAML file. Its decrypted scalar must be a **JSON object**:

   ```yaml
   radicale-agent-credentials: |
     {"username":"replace-me","password":"replace-with-secret"}
   ```

   This is an example to enter through `sops`, **not plaintext to commit**.
   [credentials.example.json](credentials.example.json) shows the file format.
   The module uses your existing `sops.defaultSopsFile` and age keys. sops-nix
   decrypts a private file; the broker opens it directly. No EnvironmentFile,
   shell export, Nix string, MCP config or sandbox mount contains credentials.
3. This repository's `home/common.nix` enables the tested Agent collection with
   writes through its lightweight `radicale-agent-common` module. It is shared
   by all Linux Home Manager profiles, including NixOS-integrated/minimal users.
   Darwin is excluded because this broker uses Linux session D-Bus/systemd.
   Individual profiles can override the shared defaults. For another deployment,
   import `flake.homeModules.radicale-agent` and configure:

   ```nix
   services.radicale-agent = {
     enable = true;
     url = "https://dav.example.net/";
     collectionUrl = "https://dav.example.net/user/discovered-id/";
     timeZone = "Asia/Tokyo";
     enableWrites = false; # Start with discovery and reads.
   };
   ```

   These non-secret settings and the **file path only** become unit environment
   variables. Each machine needs a host-side key capable of decrypting
   `secrets/home.yaml`; the shared default uses `~/.ssh/id_ed25519`.
4. Apply Home Manager. The user service requires `sops-nix.service` and is
   D-Bus activated. Restart Pi to get the new executable/PATH and proxy rules;
   already-running sandboxes retain their previous policy.
5. For a new deployment, verify reads through MCP before enabling writes.
   Then set `enableWrites = true`, apply and restart
   `radicale-agent.service` to grant single-item writes in Agent. This is a
   **host policy decision**, not a tool-accessible flag. Other collections and
   collection-management operations remain inaccessible.

The broker accepts a regular credentials file of at most 16 KiB, mode 0600 or
0400 (no group/other permission). Symlinks are allowed for sops-nix. The path
must be absolute. `CALDAV_USERNAME` and `CALDAV_PASSWORD` are not supported and
are ignored; providing only them fails closed. Secret rotation requires a broker
restart. Do not place the decrypted file in the checkout, `~/.pi`, or another
sandbox-visible directory.

### Host discovery and standalone configuration

[.env.example](.env.example) contains **non-secret settings only**:

```dotenv
CALDAV_URL=https://dav.example.net/
CALDAV_CREDENTIALS_FILE=/absolute/path/to/private/credentials.json
CALDAV_AGENT_COLLECTION_URL=https://dav.example.net/user/discovered-id/
APP_TIMEZONE=Asia/Tokyo
CALDAV_WRITES_ENABLED=false
```

The package does not load `.env` automatically. Supply these settings through
systemd or your host shell; never export credential values. To find the actual
collection URL, omit `CALDAV_AGENT_COLLECTION_URL` and run on the host:

```sh
CALDAV_URL=https://dav.example.net/ \
CALDAV_CREDENTIALS_FILE="$HOME/.config/sops-nix/secrets/radicale-agent-credentials" \
radicale-agent-discover
```

Discovery prints names, canonical URLs and supported components, never secrets.
Pin the discovered Agent URL in `collectionUrl`, then use normal tools. An
unconfigured broker refuses to run rather than expose every collection.

HTTPS is required except on loopback. Certificate verification stays enabled;
redirects are rejected, so use the canonical endpoint. Authentication is HTTP
Basic over TLS (Radicale's usual setup). `localhost` is the host broker's
network namespace, not the sandbox's.

## MCP client

Pi has built-in MCP support; no adapter package is needed. After applying Home
Manager and restarting Pi's sandbox, register the server for each profile:

```sh
pi mcp add radicale-agent --exposure direct -- radicale-agent-mcp
pi-work mcp add radicale-agent --exposure direct -- radicale-agent-mcp
pi mcp list
pi-work mcp list
```

The files are `~/.pi/agent/mcp.json` and `~/.pi/agent-work/mcp.json` respectively.
Registration persists across projects for that profile. Use `/mcp` to inspect
connections and `/reload` inside an existing session after registration.
The separately isolated `pi-subagent` launcher does not mount the desktop D-Bus
socket, so Radicale is not reachable there without additional forwarding.
`direct` makes the twelve tools
visible without tool search; default `codemode` exposure is also supported.
A project `.pi/mcp.json` may override the user-level entry. Keep the built-in MCP
extension enabled, and do not install an adapter that replaces `/mcp`.

For other clients, merge [mcp-client.example.json](mcp-client.example.json) into
their stdio configuration:

```json
{"mcpServers":{"radicale-agent":{"command":"radicale-agent-mcp","args":[]}}}
```

No credentials **or credentials file path** are needed by the MCP process.
Preserve the sandbox's `DBUS_SESSION_BUS_ADDRESS`, which points to the filtered
proxy. Home Manager enables the host broker, but the per-profile MCP registration
above is a separate step. There is no TCP MCP listener.

The wrapper grants only these exact calls, not unrestricted `--talk` access:

```text
--call=io.github.pineapplehunter.Radicale1=io.github.pineapplehunter.Radicale1.Read@/io/github/pineapplehunter/Radicale1
--call=io.github.pineapplehunter.Radicale1=io.github.pineapplehunter.Radicale1.Write@/io/github/pineapplehunter/Radicale1
```

Read rejects write actions even when writes are enabled. Write rejects reads,
unknown actions and all mutations while host write mode is off. With read-only
mode, the seven mutating MCP tools consistently return `READ_ONLY`.

## Tool contract

`collection_id` is always exactly `Agent`. All results are structured dictionaries:

```json
{"ok":true,"data":{"items":[],"truncated":false}}
```

Single-item operations also return an `items` array. UID reads return all matching
components, including recurrence overrides. Listings identify occurrences with
`uid` plus `recurrence_id`. UIDs are stable and ETags are opaque versions, never
display names. If a list result has `etag: null`, use `get_event` / `get_task`
before updating or deleting to obtain a fresh ETag.

| Tool | Arguments beyond `collection_id` |
|---|---|
| `list_collections` | none, no `collection_id` needed |
| `list_events` | `start`, `end`, `limit=200` |
| `get_event` | `uid` |
| `create_event` | `request_id`, `title`, `start`, `end`, `description=""`, `location=""` |
| `update_event` | `uid`, `changes`, `expected_etag` |
| `delete_event` | `uid`, `expected_etag` |
| `list_tasks` | `include_completed=false`, `due_before=null`, `limit=200` |
| `get_task` | `uid` |
| `create_task` | `request_id`, `title`, `due=null`, `description=""`, `priority=0` |
| `update_task` | `uid`, `changes`, `expected_etag` |
| `complete_task` | `uid`, `expected_etag` |
| `delete_task` | `uid`, `expected_etag` |

Dates are `YYYY-MM-DD`; timestamps are RFC 3339 **with offsets**, e.g.
`2026-10-20T14:00:00+09:00` or `2026-10-20T05:00:00Z`. No naive datetimes.
All-day event end is exclusive. Start/end must have matching types and positive
duration. Offset-only inputs are stored as UTC instants, avoiding unresolved
TZID names such as `UTC+09:00`. Outputs use `APP_TIMEZONE` (UTC by default);
all-day values remain dates. Existing floating times are interpreted in that
zone and marked `floating_time: true`; use explicit zones in source calendars,
especially around DST transitions.

Event read windows must be positive and <=90 days. Due filtering is exclusive
and excludes undated tasks. Task priority is 0 (unspecified), 1 (highest) through
9 (lowest). Title max 500 characters, description 16 KiB, location 2048 characters.
Inputs reject unknown fields, invalid types/dates, disallowed aliases and
oversized requests before performing relevant DAV operations.

### Writes, retries and conflicts

Create requests require a new lowercase UUID `request_id` (generate with
`uuid.uuid4()` or equivalent). It deterministically produces UID and resource
name `agent-<request_id>`. **Reuse the same ID and identical arguments after a
lost reply**; do not retry with a fresh ID. A stored request hash distinguishes
identical retries from conflicting reuse. Replaying a successful creation
returns the existing item's current state, even if subsequently updated.
Creation uses HTTP `If-None-Match: *`, not a preflight-only existence check.

Updates require the strong, last-read ETag. A fresh GET obtains data and ETag
from one snapshot; the write carries `If-Match`. The server therefore rejects a
race **after** the initial ETag comparison too. No writes are blindly retried.
On `CONFLICT`, reread and decide how to merge; do not simply force the edit.
Unspecified fields, unknown properties, categories, alarms, UID and timezone
components are preserved. Modifying event boundaries converts a related
DURATION to explicit DTEND; setting task due replaces an alternative DURATION.

`update_event.changes` permits title/start/end/description/location.
`update_task.changes` permits title/due/description/priority/status/percent_complete.
An empty changes object is invalid. Only task `due` accepts null (clear it);
use an empty string to clear descriptions/locations. Status is `NEEDS-ACTION`,
`IN-PROCESS`, `COMPLETED` or `CANCELLED`. Completion sets percent=100 and a UTC
completion timestamp. Percent 1-99 implies in-progress; 0 implies needs-action;
100 implies completed. Explicit contradictory status/percentage inputs fail.
Reopening removes the completion timestamp and resets percentage as appropriate.
Repeat completion of an already complete task returns it without a PUT, even
with the preceding ETag; it does not change its timestamp or duplicate it.

`delete_event` / `delete_task` permanently remove one item by UID, with a mandatory
strong `expected_etag` and server-enforced `If-Match`. They verify absence by UID
afterwards. Success returns an item containing `collection_id`, `uid`,
`deleted: true` and `already_absent: false`; repeating deletion of an absent UID
returns `already_absent: true` without another DELETE. A recreated/changed UID
is not deleted with an old ETag. Deletion tools have MCP destructive annotations
and require the same host write opt-in as other mutations; no extra flag is needed.

Recurring resources, overrides, multi-component resources and scheduled items
with METHOD/ORGANIZER/ATTENDEE remain read-only, including deletion. No invitation
or attachment editing, collection management, arbitrary HTTP/iCalendar or bulk
mutation tools.
Each mutation must reflect explicit user intent. Host opt-in authorizes the
broker's same-user callers; there is no independent per-action confirmation UI.

## Errors, resource limits and security

```json
{"ok":false,"error":{"code":"CONFLICT","message":"Refresh the resource and retry."}}
```

Public codes include `INVALID_INPUT`, `FORBIDDEN`, `AUTH_FAILED`, `NOT_FOUND`,
`CONFLICT`, `UNSUPPORTED_COMPONENT`, `UNSUPPORTED_DATA`, `UNSUPPORTED_RECURRENCE`,
`READ_ONLY`, `RESULT_TOO_LARGE`, `BUSY`, `SERVER_UNAVAILABLE`, `BROKER_UNAVAILABLE`,
`CONFIG_ERROR`, `INTERNAL_ERROR`. MCP schema errors use the SDK's standard tool
error. Raw HTTP bodies, tracebacks and credential values are never returned.
Logs contain timestamp, action, alias, UID and result, not private descriptions.
Library communication dumps are disabled.

Requests are capped at 64 KiB, results at 200 items and 2 MiB (`truncated` indicates
more items existed). No pagination yet. DAV responses/recurrence expansion can
consume more memory before the output cap; do not treat this as a strong
CPU/memory quota for huge collections. Task queries are collection-scoped,
not server-side paginated. One broker operation runs at a time; overlap returns
`BUSY`. Each HTTP request has a 10-second timeout; multi-request operations may
take longer. The MCP-to-broker timeout is 90 seconds. After any uncertain write
result, reread/reuse the creation request ID before deciding to retry.

Calendar contents are untrusted data, never instructions. Other processes of
the desktop user can call this session-bus service too: this is not per-agent
identity or protection against a compromised host user. Never pass an unrestricted
host bus or mount the credentials file into the agent sandbox.

## Development and testing

Python >=3.11; caldav 3.3.1, icalendar 7.2.2, dbus-next 0.2.3 and official MCP SDK
**v1.29.0** (`FastMCP`, not SDK v2). `uv.lock` pins standalone dependencies;
`flake.lock` pins Nix dependencies. From this directory:

```sh
nix shell nixpkgs#uv nixpkgs#dbus nixpkgs#xdg-dbus-proxy nixpkgs#nss_wrapper
export RADICALE_TEST_NSS_WRAPPER="$(nix eval --raw nixpkgs#nss_wrapper.outPath)/lib/libnss_wrapper.so"
uv sync --locked
uv run pytest -q
```

Local tests never contact Radicale. They use real iCalendar parsing, local HTTP
precondition/error fixtures, a fake DAV backend and actual filtered D-Bus + MCP
stdio round trips for all twelve tools. The transport test requires dbus-run-session
and xdg-dbus-proxy; missing tools cause a skip. Tests require neither Bubblewrap
nor user namespaces. When the current UID has no passwd entry (as in Pi),
`nss_wrapper` supplies temporary passwd/group data through the child process's
NSS environment and `LD_PRELOAD`, without filesystem mounts. Set
`RADICALE_TEST_NSS_WRAPPER` to `libnss_wrapper.so` in that case; otherwise the
transport check skips with instructions. Normal systems with a passwd entry
need no wrapper. Nix package checks supply the library path automatically.

From repository root (stage new Nix-referenced source files first):

```sh
nix build --no-link .#legacyPackages.x86_64-linux.radicale-agent
nix flake check --no-build --all-systems
```

### Opt-in live tests

**These create/modify uniquely named test fixtures in Agent.** Approve this first;
never point them at a personal collection. Deletion checks and the MCP roundtrip
remove only their own freshly created fixtures; other live checks leave fixtures
for manual cleanup. No pre-existing item is edited or deleted. Authentication
uses a file, not credential environment values:

```sh
export CALDAV_URL=https://dav.example.net/
export CALDAV_CREDENTIALS_FILE=/absolute/path/to/private/credentials.json
export CALDAV_AGENT_COLLECTION_URL=https://dav.example.net/user/discovered-id/
export APP_TIMEZONE=Asia/Tokyo
export CALDAV_WRITES_ENABLED=true
export RADICALE_LIVE_TEST=1
export RADICALE_LIVE_WRITE_TEST=1
# Optional record of this run's non-secret fixture UIDs:
export RADICALE_LIVE_FIXTURE_LOG=/tmp/radicale-agent-test-uids.jsonl
uv run pytest -q -m live --tb=short
```

Set only `RADICALE_LIVE_TEST=1` to run discovery without authorizing live writes.
For Inspector, connect stdio to `radicale-agent-mcp` in the deployed desktop
session. Diagnostics: `systemctl --user status radicale-agent` and
`journalctl --user -u radicale-agent`. `BROKER_UNAVAILABLE` usually means a missing
secret, unconfigured/stopped host unit, stale Pi wrapper or bus policy denial.
