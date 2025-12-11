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
      age.secrets = {
        garage-secret = {
          file = flake-config.ageFile.garage-secret;
          mode = "0400";
          owner = "garage";
          group = "garage";
        };
      };

      services.garage = {
        enable = true;
        package = pkgs.garage_2;
        settings = lib.importTOML ./garage-config.toml;
        environmentFile = config.age.secrets.garage-secret.path;
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
