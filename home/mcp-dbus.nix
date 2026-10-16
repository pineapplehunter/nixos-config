{ ... }:
{
  flake.homeModules.mcp-dbus =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.mcp-dbus;
      servers = lib.filterAttrs (_: server: server.enable) cfg.servers;
    in
    {
      key = "nixos-config/home/mcp-dbus";
      options.services.mcp-dbus.servers = lib.mkOption {
        default = { };
        description = "Host MCP stdio servers exposed over the session bus. Commands and credentials are host-only.";
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
              };
              busName = lib.mkOption {
                type = lib.types.str;
                description = "Dedicated well-known D-Bus name for this backend.";
              };
              command = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "Fixed host-side MCP executable and arguments; use an absolute executable path.";
              };
              environment = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
                description = "Host-only backend environment. Reference secret files, not plaintext secrets.";
              };
              requires = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "User services that must start before this backend.";
              };
            };
          }
        );
      };

      config = lib.mkIf (servers != { }) {
        assertions = [
          {
            assertion = pkgs.stdenv.hostPlatform.isLinux;
            message = "mcp-dbus requires Linux and a session D-Bus.";
          }
          {
            assertion = lib.all (server: server.command != [ ]) (lib.attrValues servers);
            message = "Each mcp-dbus backend requires a fixed command.";
          }
          {
            assertion =
              lib.length (lib.unique (map (server: server.busName) (lib.attrValues servers)))
              == lib.length (lib.attrNames servers);
            message = "mcp-dbus backends must have distinct bus names.";
          }
        ];
        home.packages = [ pkgs.mcp-dbus-proxy ];
        systemd.user.services = lib.mapAttrs' (
          name: server:
          lib.nameValuePair "mcp-${name}" {
            Unit = {
              Description = "Host MCP bridge: ${name}";
              After = server.requires;
              Requires = server.requires;
            };
            Service = {
              Type = "dbus";
              BusName = server.busName;
              ExecStart = lib.escapeShellArgs (
                [
                  (lib.getExe' pkgs.mcp-dbus-proxy "mcp-dbus-host")
                  "--service"
                  server.busName
                  "--"
                ]
                ++ server.command
              );
              Environment = lib.mapAttrsToList (key: value: "${key}=${value}") server.environment;
              NoNewPrivileges = true;
              PrivateTmp = true;
              UMask = "0077";
            };
          }
        ) servers;
        xdg.dataFile = lib.mapAttrs' (
          name: server:
          lib.nameValuePair "dbus-1/services/${server.busName}.service" {
            text = ''
              [D-BUS Service]
              Name=${server.busName}
              Exec=${pkgs.systemd}/bin/systemctl --user start mcp-${name}.service
              SystemdService=mcp-${name}.service
            '';
          }
        ) servers;
      };
    };
}
