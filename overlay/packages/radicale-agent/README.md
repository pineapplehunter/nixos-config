# Radicale Agent MCP

A normal MCP stdio server for the existing CalDAV collection named `Agent`, pinned
by exact URL. Authorization and file-only credentials are handled by the server
on the host. No collection creation/deletion or Radicale server changes.

## Architecture

```text
Sandbox MCP client -> mcp-dbus-proxy (no credentials)
  -> filtered session D-Bus -> generic mcp-dbus-host
  -> radicale-agent-mcp (normal MCP stdio, host credentials and policy)
  -> CalendarService -> python-caldav + icalendar -> Radicale over verified HTTPS
```

The backend also works directly over stdio on the host with no D-Bus dependency.
See [the bridge documentation](../mcp-dbus-proxy/README.md) for transport details.
The original [implementation plan](IMPLEMENTATION_PLAN.md) records historical
verification and the superseded application-specific D-Bus architecture.

## Home Manager and credentials

Import `flake.homeModules.radicale-agent` and configure:

```nix
services.radicale-agent = {
  enable = true;
  url = "https://dav.example.net/";
  collectionUrl = "https://dav.example.net/user/discovered-id/";
  timeZone = "Asia/Tokyo";
  enableWrites = false;
};
```

Add `radicale-agent-credentials` to your encrypted Home Manager SOPS YAML using
`sops`. The decrypted scalar is a JSON object:

```yaml
radicale-agent-credentials: |
  {"username":"replace-me","password":"replace-with-secret"}
```

Do not commit plaintext credentials. [credentials.example.json](credentials.example.json)
shows the format. The backend accepts an absolute path to a regular file of at
most 16 KiB, mode 0600 or 0400; sops-nix symlinks are supported. Credential values
are never read from `CALDAV_USERNAME` or `CALDAV_PASSWORD`. Only the file path
enters the host unit environment. Never put this file in the checkout or `~/.pi`.

The shared `radicale-agent-common` module in `home/common.nix` enables the
configured Agent collection and writes for Linux profiles, including minimal
homes. Profiles can override those defaults. The module creates the D-Bus
activated `mcp-radicale-agent.service`, requiring `sops-nix.service`.

Apply Home Manager and restart Pi to get new executable paths and bus rules.
For a new deployment, verify reads before enabling writes. Write mode is a host
configuration decision, not a tool argument. Restart the host service after
configuration changes or secret rotation; active backend sessions are terminated.

### Standalone host use and discovery

Supply the non-secret settings in [.env.example](.env.example) through the host
shell or systemd (the package does not automatically load `.env`):

```sh
export CALDAV_URL=https://dav.example.net/
export CALDAV_CREDENTIALS_FILE=/absolute/path/to/private/credentials.json
export CALDAV_AGENT_COLLECTION_URL=https://dav.example.net/user/discovered-id/
export APP_TIMEZONE=Asia/Tokyo
export CALDAV_WRITES_ENABLED=false
radicale-agent-mcp
```

For administrative discovery, run `radicale-agent-discover` on the host; the
collection URL may be omitted. It prints names, URLs, and component support, not
credentials. Discovery is not an agent tool. HTTPS is required except on
loopback; TLS verification stays enabled and redirects are rejected.

## MCP client configuration

Pi Home Manager activation merges all enabled host MCP services into both
`~/.pi/agent/mcp.json` and `~/.pi/agent-work/mcp.json`, preserving unrelated entries.
Tools have `direct` exposure and a 90-second request timeout. No Pi adapter or
application-specific extension is needed. Use `pi mcp list` or `/mcp` to inspect.
A project MCP configuration can override a user entry. Keep built-in MCP enabled.

For other clients, use [mcp-client.example.json](mcp-client.example.json):

```json
{"mcpServers":{"radicale-agent":{"command":"mcp-dbus-proxy","args":["--service","io.github.pineapplehunter.McpRadicale1"]}}}
```

Only the bridge process runs inside the sandbox. It needs the filtered
`DBUS_SESSION_BUS_ADDRESS`, never credentials or their file path. The separately
isolated `pi-subagent` launcher does not forward the desktop bus and cannot reach
these services. No TCP listener is exposed.

The old `radicale-agentd`, `Radicale1.Read`, and `Radicale1.Write` API is removed.
The wrapper now grants the four generic bridge methods on the Radicale endpoint.
All twelve tools remain available, including in read-only mode; mutations return
`READ_ONLY` when host writes are disabled. Tool annotations are not authorization.

## Tool contract and host policy

Collection ID is exactly `Agent`. Its URL and discovered display name must both
match host configuration. The agent cannot choose another URL, credentials, or
write mode. Inputs are validated again by `CalendarService`, not just MCP schemas.

| Tool | Arguments beyond `collection_id` |
|---|---|
| `list_collections` | none; no `collection_id` needed |
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

Results use `{"ok":true,"data":{"items":[],"truncated":false}}` or
`{"ok":false,"error":{"code":"CONFLICT","message":"..."}}`. Single-item results
also use `items`. UIDs are stable and ETags are opaque versions. If a listing has
`etag: null`, get the item before modifying it.

Dates are `YYYY-MM-DD`; timestamps must have RFC 3339 offsets. All-day end dates
are exclusive. Event windows are positive and at most 90 days. Task due filters
are exclusive and omit undated tasks. Priority is 0 (unspecified), 1 (highest)
through 9. Titles are limited to 500 characters, descriptions to 16 KiB, and
locations to 2048 characters. Results are capped at 200 items and 2 MiB; requests
at 64 KiB. DAV retrieval/recurrence expansion can consume more memory before the
output cap. There is no pagination.

Creates require a new lowercase UUID `request_id`. It determines the stable UID
`agent-<request_id>` and resource name. Reuse the ID and identical arguments after
a lost reply, not a fresh ID. A request hash rejects conflicting reuse; creation
uses HTTP `If-None-Match: *`.

Updates and deletes require a strong, last-read `expected_etag`; HTTP `If-Match`
protects against concurrent clients. On `CONFLICT`, reread before deciding what
to do. Unspecified fields, unknown properties, alarms, categories, and timezone
components are preserved. Only task `due` accepts null (clear it). Task updates
support status and completion percentages; contradictory values fail. Completion
sets status, percentage, and timestamp, and repeat completion does not rewrite.

Deletes remove one non-recurring item and verify UID absence. Results include
`deleted` and `already_absent`; repeated deletion of an absent item succeeds,
while an old ETag cannot delete a changed/recreated item. Recurring resources,
overrides, multi-component resources, and scheduled items remain read-only.
There are no bulk mutations, arbitrary HTTP/iCalendar, or attachment/invitation
tools. Calendar contents are untrusted data, never instructions.

A shared host file lock serializes calendar operations across MCP sessions;
overlap returns `BUSY`. The lock remains owned by the worker until the operation
finishes even if the MCP request is cancelled. Each HTTP request has a 10-second
timeout; multi-request operations can take longer. Disconnect/cancellation does
not roll back a write. Never blindly replay uncertain mutations.

Raw HTTP bodies, exception text, and credential values are not returned. Audit
logs contain action, alias, UID, and result, not private descriptions. The host
policy applies to all callers; no per-tool agent approval gate is introduced.
Other unsandboxed processes of the same host user are outside this boundary.

## Verification

The Nix package check exercises policy, parsing, conditional writes, and all
twelve tools over the generic bridge with a fake DAV backend and real filtered
private D-Bus. No real credentials or remote writes are used. It also verifies
cross-session serialization and sanitized configuration failures.

```sh
nix build --no-link .#legacyPackages.x86_64-linux.radicale-agent
nix flake check --no-build --all-systems
```

For standalone development, `uv sync --locked` installs the sibling bridge as a
dev dependency. Transport tests also need `dbus-run-session`, `xdg-dbus-proxy`, and
(on minimal systems without passwd entries) `RADICALE_TEST_NSS_WRAPPER` pointing
to `libnss_wrapper.so`. Nix supplies these automatically.

Live tests are opt-in and **create/modify fixtures in Agent**. Approve them first.
Set `RADICALE_LIVE_TEST=1` for discovery; add `RADICALE_LIVE_WRITE_TEST=1` and host
CalDAV configuration to authorize fixture mutations. `RADICALE_LIVE_FIXTURE_LOG`
can record test UIDs. Deletion/MCP checks remove their own fixtures; other live
checks may leave fixtures requiring cleanup. No pre-existing item is edited.

Diagnostics: `systemctl --user status mcp-radicale-agent` and
`journalctl --user -u mcp-radicale-agent`. Check secrets, service configuration,
and stale Pi bus rules after a failed bridge connection.
