{ inputs, config, ... }:
let
  mcpModule = config.flake.homeModules.mcp-dbus;
in
{
  flake.homeModules.radicale-agent =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.services.radicale-agent;
    in
    {
      imports = [
        inputs.sops-nix.homeManagerModules.sops
        mcpModule
      ];
      options.services.radicale-agent = {
        enable = lib.mkEnableOption "host CalDAV MCP server restricted to the Agent collection";
        url = lib.mkOption {
          type = lib.types.str;
          description = "Canonical CalDAV endpoint, without credentials.";
          example = "https://dav.example.net/";
        };
        collectionUrl = lib.mkOption {
          type = lib.types.str;
          description = "Exact discovered URL of the existing collection named Agent.";
          example = "https://dav.example.net/user/discovered-id/";
        };
        timeZone = lib.mkOption {
          type = lib.types.str;
          default = "UTC";
          description = "Timezone for date boundaries and normalized output.";
        };
        enableWrites = lib.mkEnableOption "conditional event/task writes after read verification";
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = pkgs.stdenv.hostPlatform.isLinux;
            message = "radicale-agent requires Linux and a session D-Bus.";
          }
        ];
        home.packages = [ pkgs.radicale-agent ];
        # The ordinary MCP backend reads this file on the host only.
        sops.secrets.radicale-agent-credentials = { };
        services.mcp-dbus.servers.radicale-agent = {
          busName = "io.github.pineapplehunter.McpRadicale1";
          command = [ (lib.getExe pkgs.radicale-agent) ];
          requires = [ "sops-nix.service" ];
          environment = {
            CALDAV_URL = cfg.url;
            CALDAV_AGENT_COLLECTION_URL = cfg.collectionUrl;
            APP_TIMEZONE = cfg.timeZone;
            CALDAV_WRITES_ENABLED = lib.boolToString cfg.enableWrites;
            CALDAV_CREDENTIALS_FILE = config.sops.secrets.radicale-agent-credentials.path;
          };
        };
      };
    };
}
