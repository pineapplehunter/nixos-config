# Radicale integration: original sandbox-aware implementation plan

> Historical record: the application-specific broker/facade architecture below
> has been replaced by a standalone host MCP server behind the shared
> [MCP D-Bus bridge](../mcp-dbus-proxy/README.md). See [README.md](README.md) for
> current deployment, policy, and testing instructions.

Adapted from the supplied `RADICALE_AGENT_IMPLEMENTATION_GUIDE.md`, then updated
for the user's explicit Agent-only, write-support and file-credentials requests.

## Architecture and policy

```text
Agent / MCP client in Pi sandbox
  -> official MCP SDK v1 stdio facade (no secrets or credential-file path)
  -> filtered session D-Bus, exact Radicale1.Read / Radicale1.Write calls
  -> host broker: validation + fixed collection policy + CalendarService
  -> python-caldav + icalendar -> existing Radicale over verified HTTPS
```

- Only collection ID `Agent` is accepted. The host pins its discovered canonical
  URL and verifies display name `Agent`; neither another alias nor another
  same-name collection grants access. Policy is not agent-editable.
- Username/password are read from a private **JSON file**, delivered by sops-nix.
  Only `CALDAV_CREDENTIALS_FILE` (the path) enters the host environment; credential
  values never do. Other host env settings are non-secret URL/timezone/policy.
- No decrypted file/Nix plaintext secrets in the repository, Nix store, MCP
  config, sandbox mounts or sandbox environment. Standalone `.env.example`
  contains non-secret settings only.
- Read is always read-only. A separate Write method requires host opt-in,
  `CALDAV_WRITES_ENABLED=true` / Home Manager `enableWrites=true` (default false).
  MCP write tools reject consistently until enabled. Host policy authorizes
  same-user service callers, not per-agent identity or independent human approval.
  Tool descriptions require explicit user intent; the user authorized live tests.
- No Radicale reinstall/server changes, rights changes, collection management,
  bulk writes, raw HTTP/iCalendar tools, invitations or attachment edits.

## Implemented increments

### 1. Read-only foundation

Configuration, secure file loading, host-only discovery, component inspection,
fixed collection authorization, event windows/recurrence display, exact UID
lookups, task due/priority/completion normalization, JSON errors, audit metadata,
D-Bus broker, MCP facade, opt-in Home Manager service and documentation.

### 2. Single-item writes

- Typed create and partial-update models, timezone/date/type/range validation,
  priorities 0-9, allowed fields, non-recurring and non-scheduled restrictions.
- Stable UID/resource URL from UUID request_id and immutable creation fingerprint.
  Same inputs/ID safely replay; conflicting ID reuse fails. No blind retries.
- Conditional create (`If-None-Match: *`) and update (`If-Match`). Fresh GET data
  and ETag are one snapshot. A preflight comparison alone is not the guarantee.
- Event create/update; task create/update/complete/reopen; consistent completion
  percentage/status/timestamp. Repeated completion performs no PUT.
- Unknown properties, categories, alarms, UID and timezone components preserved.
  Related DURATION conversion is explicit when changing event boundaries/task due.
- Scoped DAV adapter permits conditional PUTs and single-item DELETEs directly
  inside Agent. DELETE requires If-Match; MKCALENDAR/PROPPATCH and collection
  deletion remain blocked.
- Separate narrow D-Bus Write proxy rule; credentials stay in the host broker.

### 3. Single-item deletion (explicitly requested after the initial scope)

`delete_event` and `delete_task` use the existing host write opt-in and narrow
D-Bus Write method. They require a fresh strong ETag, refuse recurring/scheduled
and multi-component resources, issue conditional DELETE and verify UID absence.
Repeated deletion of an absent UID succeeds without a second DELETE; stale or
recreated UIDs cannot be removed with an old ETag. MCP marks these tools
explicitly destructive. No collection or bulk deletion is exposed.

The deletion follow-up passed 89 local checks and four live checks, including
both component types, retries, an actual concurrent DELETE conflict and all
twelve MCP tools through the filtered bus. New fixtures were verified absent.

## Verification gates and results

1. Unit policy/validation/normalization, mutation preservation/idempotency/race
   tests, and sanitized error tests.
2. Real python-caldav against local HTTP fixtures verifying actual precondition
   headers, forbidden methods/URLs and structured HTTP error mapping.
3. Actual MCP client/server over stdio + private D-Bus + xdg-dbus-proxy, exercising
   all twelve tools with a fake backend, and again with the live Radicale backend.
4. Package tests/build, all-systems Nix evaluation and enabled Home Manager unit
   evaluation with no credentials in Environment or EnvironmentFile.
5. Live tests against the existing user-approved Agent collection. Only unique
   `[Agent integration test]` fixtures are created/modified; no pre-existing data
   is edited/deleted and no collection/server changes occur. Deletion and MCP
   checks clean up only their own fresh fixtures.

On 2026-10-16, local tests and seven live checks passed: discovery/scope, timed
event roundtrip/preservation, all-day roundtrip, task lifecycle, actual server
If-Match race, recurring series/override read with write rejection, and all MCP
tools through the filtered bus. An independent HTTP/iCalendar client verifies
stored data outside the service normalizer. Credentials were supplied to these
live tests by file path, not credential environment variables.

Live testing exposed and fixed missing ETags from UID REPORT lookups (now fresh
GET), and unresolved offset-only TZIDs (now serialize input instants as UTC).
Test fixture UIDs can be logged to RADICALE_LIVE_FIXTURE_LOG. Original fixtures
were subsequently cleaned up at the user's request. Future non-deletion live
checks can leave fixtures for cleanup; deletion/MCP checks remove their own.

## Still out of scope / not verified

- Recurrence/override and scheduled-item deletion or editing; invitation and
  attachment editing; collection management, bulk mutation, notifications or
  remote HTTP MCP.
- Interactive GUI/Inspector display and deployed desktop systemd activation.
  A private test broker is not evidence that the desktop unit was activated.
- Strong DAV response/recurrence memory quotas and pagination for huge collections.
- Per-action approval UI or per-agent D-Bus identity. Same-user host compromise
  is outside this trust boundary.

Keep SDK v1 pinned; current stack is Python >=3.11, caldav 3.3.1, icalendar 7.2.2,
MCP 1.29.0 and dbus-next 0.2.3. Standalone dependencies use uv.lock, Nix uses the
repository flake.lock. Do not claim additional features working without tests.
