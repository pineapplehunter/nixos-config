{ config, ... }:
let
  flake-config = config;
in
{
  flake.nixosModules.rpi5-garage =
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
          mode = "0400";
          owner = "garage";
          group = "garage";
        };
        garage-admin-token = {
          sopsFile = flake-config.sopsFile.garage-secret;
          key = "admin-token";
          mode = "0400";
          owner = "garage";
          group = "garage";
        };
      };

      services.garage = {
        enable = true;
        package = pkgs.garage_2;
        settings = lib.mkMerge [
          (lib.importTOML ./garage-config.toml)
          {
            rpc_secret_file = config.sops.secrets.garage-rpc-secret.path;
            admin.admin_token_file = config.sops.secrets.garage-admin-token.path;
          }
        ];
        logLevel = "error";
      };

      systemd.services.garage = {
        serviceConfig = {
          User = "garage";
          Group = "garage";
          DynamicUser = false;
          RestartSec = "1min";
          Restart = "always";
        };
        wantedBy = lib.mkForce [ "default.target" ];
      };

      users.users.garage = {
        isSystemUser = true;
        group = "garage";
      };

      users.groups.garage = { };
    };
}
