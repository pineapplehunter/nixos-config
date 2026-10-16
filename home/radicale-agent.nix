{ inputs, ... }:
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
      imports = [ inputs.sops-nix.homeManagerModules.sops ];
      options.services.radicale-agent = {
        enable = lib.mkEnableOption "host CalDAV broker restricted to the Agent collection";
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
        # Decrypted content is a JSON object with username/password. It is
        # opened by the broker, NEVER loaded into systemd's environment.
        sops.secrets.radicale-agent-credentials = { };
        systemd.user.services.radicale-agent = {
          Unit = {
            Description = "Agent collection CalDAV broker";
            After = [ "sops-nix.service" ];
            Requires = [ "sops-nix.service" ];
          };
          Service = {
            Type = "dbus";
            BusName = "io.github.pineapplehunter.Radicale1";
            ExecStart = lib.getExe' pkgs.radicale-agent "radicale-agentd";
            Environment = [
              "CALDAV_URL=${cfg.url}"
              "CALDAV_AGENT_COLLECTION_URL=${cfg.collectionUrl}"
              "APP_TIMEZONE=${cfg.timeZone}"
              "CALDAV_WRITES_ENABLED=${lib.boolToString cfg.enableWrites}"
              "CALDAV_CREDENTIALS_FILE=${config.sops.secrets.radicale-agent-credentials.path}"
            ];
            NoNewPrivileges = true;
            PrivateTmp = true;
            UMask = "0077";
          };
        };
        xdg.dataFile."dbus-1/services/io.github.pineapplehunter.Radicale1.service".text = ''
          [D-BUS Service]
          Name=io.github.pineapplehunter.Radicale1
          Exec=${pkgs.systemd}/bin/systemctl --user start radicale-agent.service
          SystemdService=radicale-agent.service
        '';
      };
    };
}
