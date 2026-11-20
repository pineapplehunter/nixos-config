{
  pkgs,
  codexHost,
  state,
  legacy,
}:
let
  inherit (pkgs) lib;
  # Reuse the exact TUI build shipped with the host Pi, including its native runtime.
  tui = pkgs.replaceVars ./codex-auth-tui.mjs {
    PI_TUI = "${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo/node_modules/@earendil-works/pi-tui/dist/index.js";
  };
in
pkgs.writeShellApplication {
  name = "pi-codex-auth";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.jq
  ];
  text = ''
    state=${lib.escapeShellArg state}
    legacy=${lib.escapeShellArg legacy}
    pi=${lib.escapeShellArg (lib.getExe pkgs.pi-coding-agent)}
    node=${lib.escapeShellArg (lib.getExe pkgs.nodejs)}
    codex_host=${lib.escapeShellArg (toString codexHost)}
    tui=${lib.escapeShellArg (toString tui)}
    ${builtins.readFile ./codex-auth.sh}
  '';
}
