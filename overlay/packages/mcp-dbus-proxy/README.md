# Host MCP D-Bus bridge

Run normal MCP stdio servers on the host without giving agents their credentials.
The sandbox runs `mcp-dbus-proxy --service BUS_NAME`; a host-only
`mcp-dbus-host --service BUS_NAME -- /absolute/backend arguments` launches one
stdio backend per connection. There is no TCP listener or MCP-specific dispatch
in the bridge. Initialization, tools, resources, requests in either direction,
notifications, and cancellation are forwarded as newline-delimited messages.

## Home Manager

Import `flake.homeModules.mcp-dbus`, then declare:

```nix
services.mcp-dbus.servers.example = {
  busName = "io.github.pineapplehunter.McpExample1";
  command = [ "${pkgs.example-mcp}/bin/example-mcp" ];
  environment.TOKEN_FILE = config.sops.secrets.example-token.path;
  requires = [ "sops-nix.service" ];
};
```

Use secret **file paths**, never secret contents, in Nix. Configuration and secret
paths are only passed to the host process. A backend should avoid putting secrets
in MCP responses or stderr (stderr goes to its host journal).

Pi's wrapper grants access to every enabled backend declared in this module.
Configure the MCP client with command `mcp-dbus-proxy`, arguments
`["--service", "io.github.pineapplehunter.McpExample1"]`. Other stdio clients work
with the same command. Direct host-side use of the backend needs no bridge.

## Boundary and lifecycle

Authorization belongs to the host MCP server, **not** the agent or bridge. All
backend tools are available; no agent-side tool filter or confirmation gate is
introduced. Tool annotations are metadata, not authorization. Only configured
backend commands can be launched; callers cannot choose executable, environment,
working directory, or credential files. This is not a defense against other
unsandboxed processes running as the same host user.

Each backend owns a separate bus name and uses interface
`io.github.pineapplehunter.Mcp1`, path `/io/github/pineapplehunter/Mcp1`:

- `Open() -> s`: allocate a session and launch the configured backend.
- `Send(ss)`: session ID and one newline-free MCP message.
- `Receive(s) -> s`: next message, or empty string after a 20-second long poll.
- `Close(s)`: stop the backend process group.

Sessions belong to the D-Bus caller's unique name; IDs alone grant no access.
Disconnecting kills that caller's backend groups. Limits are 64 sessions per
service, 16 per caller, 8 queued output messages per session, and 8 MiB per message
(including its stdio newline). This accommodates application results represented
as both MCP text and structured content. Input and output are independent so server requests
and cancellation do not deadlock behind a tool call. Close/exit is not a rollback:
a remote write can finish despite cancellation. Calls are never replayed after a
transport failure. Reconnection creates a new MCP session.

The sandbox bus filter allows exactly `Open`, `Send`, `Receive`, and `Close` on
each configured bus name/interface/path. Introspection and unrelated services
remain inaccessible. No broad `--talk` rule is needed.

## Checks

The Nix package check runs a private D-Bus with real `xdg-dbus-proxy` filtering,
two simultaneous MCP clients, tool/resource roundtrips, cancellation, session
ownership checks, and disconnect cleanup. It never touches the desktop bus or
real credentials.
