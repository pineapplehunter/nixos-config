{ config, ... }:
let
  flake-config = config;
in
{
  flake.nixosModules.beast-immich-related =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      age.secrets = {
        geesefs-creds = {
          file = flake-config.ageFile.geesefs-creds;
          mode = "0400";
        };
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

      # to startup immich at boot
      systemd.services = {
        immich-up = {
          enable = true;
          restartIfChanged = false;
          path = with pkgs; [
            docker
            docker-compose
          ];
          requires = [ "docker.socket" ];
          after = [
            "geesefs-mount.service"
            "docker.socket"
          ];
          script = ''
            docker compose up
          '';
          preStop = ''
            docker compose down
          '';
          serviceConfig = {
            WorkingDirectory = "/home/shogo/immich";
            Restart = "always";
            TimeoutSec = 600;
          };
          wantedBy = [ "default.target" ];
        };
      };
    };
}
