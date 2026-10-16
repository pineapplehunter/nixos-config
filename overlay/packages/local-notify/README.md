# Host notifications

`local-notify-mcp` is a normal MCP stdio server exposing
`notify(title, content, color?)`. It reads a host-only webhook file; agents cannot
choose the webhook, username, or avatar. It uses the same validation and Discord
payload implementation as the existing `local-notify` CLI.

```sh
local-notify-mcp --webhook-file /absolute/private/webhook-file
```

Optional host arguments: `--username` (default `pi`) and `--icon` (default Pi icon).
The tool supports Discord Markdown; success color is `#57F287`, failure is
`#ED4245`, and neutral messages omit color. Discord limits and hostname-suffixed
titles are validated on the host. Mentions are disabled. Transport exceptions
are sanitized before returning tool errors. Delivery is not idempotent: never
blindly retry after an uncertain result.

The common Linux Home Manager profile exposes it via
`services.mcp-dbus.servers.notifications`, using the existing SOPS
`pueue-discord-webhook` secret. The resulting `mcp-notifications.service` is
D-Bus activated and requires `sops-nix.service`. Pi automatically registers it in
both profiles with direct tool exposure as `mcp__notifications__notify`.

Other sandbox MCP clients can use:

```json
{"mcpServers":{"notifications":{"command":"mcp-dbus-proxy","args":["--service","io.github.pineapplehunter.McpNotify1"]}}}
```

The [generic bridge](../mcp-dbus-proxy/README.md) carries MCP messages; authorization
and credentials stay on the host. There is no agent-side approval gate.

`local-notify` and `local-notifyd` remain available for Pueue callbacks and other
non-MCP callers. The Pi-specific `notify.ts` extension is no longer needed.

Package checks exercise real MCP stdio with mocked delivery, schema/validation
errors, secret-safe delivery failures, and the existing CLI's Discord payload.
They do not send real Discord notifications. Diagnostics:
`journalctl --user -u mcp-notifications`.
