{ config, ... }:
let
  flake-config = config;
in
{
  flake.nixosModules.beast-garage =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      sops.secrets = {
        garage-rpc-secret = {
          sopsFile = flake-config.sopsFile.garage-secret;
          key = "rpc-secret";
          mode = "0440";
          owner = "garage";
          group = "garage";
        };
        garage-admin-token = {
          sopsFile = flake-config.sopsFile.garage-secret;
          key = "admin-token";
          mode = "0440";
          owner = "garage";
          group = "garage";
        };
      };

      users = {
        users.garage = {
          isSystemUser = true;
          group = "garage";
        };
        groups.garage = { };
      };

      networking.firewall.interfaces = {
        "tailscale0".allowedTCPPortRanges = [
          # Original ports
          {
            from = 3900;
            to = 3905;
          }
          # Proxied ports
          {
            from = 3950;
            to = 3955;
          }
        ];
        "wlp36s0".allowedTCPPortRanges = [
          {
            from = 3900;
            to = 3905;
          }
        ];
      };

      services = {
        garage = {
          enable = true;
          package = pkgs.garage_2;
          settings = lib.mkMerge [
            (lib.importTOML ./garage-config.toml)
            {
              rpc_secret_file = config.sops.secrets.garage-rpc-secret.path;
              admin.admin_token_file = config.sops.secrets.garage-admin-token.path;
            }
          ];
        };

        snapper.configs.garage = {
          SUBVOLUME = "/garage";
          ALLOW_USERS = [ "shogo" ];
          TIMELINE_CREATE = true;
          TIMELINE_CLEANUP = true;
          TIMELINE_LIMIT_HOURLY = 3;
          TIMELINE_LIMIT_DAILY = 2;
          TIMELINE_LIMIT_WEEKLY = 0;
          TIMELINE_LIMIT_MONTHLY = 3;
          TIMELINE_LIMIT_YEARLY = 0;
        };
      };

      systemd.services.garage = {
        serviceConfig = {
          User = "garage";
          Group = "garage";
          DynamicUser = false;
          RestartSec = "1min";
          Restart = "always";
        };
        environment.GARAGE_ALLOW_WORLD_READABLE_SECRETS = "true";
        wantedBy = lib.mkForce [ "default.target" ];
      };
    };
}
