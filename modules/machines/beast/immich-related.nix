{ config, ... }:
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
          file = config.ageFile.geesefs-creds;
          mode = "0400";
        };
        garage-secret = {
          file = config.ageFile.garage-secret;
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
        geesefs-mount = {
          restartIfChanged = false;
          path = with pkgs; [
            fuse
            geesefs
            util-linux
          ];
          requires = [ "garage.service" ];
          after = [ "garage.service" ];
          script = ''
            findmnt mnt && umount mnt || true
            geesefs \
              --endpoint http://localhost:3900 \
              --region garage \
              --list-type 2 \
              --memory-limit ${toString (1024 * 4)} \
              --stat-cache-ttl 10m \
              --cache mnt-cache \
              --http-timeout 0 \
              --print-stats 5m \
              --shared-config ${config.age.secrets.geesefs-creds.path} \
              -o allow_other \
              immich: \
              mnt
            ls mnt
          '';
          serviceConfig = {
            Type = "forking";
            WorkingDirectory = "/home/shogo/immich";
            TimeoutSec = 600;
            Restart = "always";
          };
        };
        immich-up = {
          enable = true;
          restartIfChanged = false;
          path = with pkgs; [
            curl
            docker
            docker-compose
          ];
          requires = [
            "geesefs-mount.service"
            "docker.socket"
          ];
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
