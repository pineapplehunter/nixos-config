{
  pkgs,
  config,
  lib,
  ...
}:
{
  age.secrets = {
    geesefs-creds = {
      file = ../../secrets/geesefs-creds.age;
      mode = "0400";
    };
    garage-secret = {
      file = ../../secrets/garage-secret.age;
      mode = "0400";
      owner = "garage";
      group = "garage";
    };
  };

  services.garage = {
    enable = true;
    package = pkgs.garage_2_0_0;
    settings = lib.importTOML ./garage-config.toml;
    environmentFile = config.age.secrets.garage-secret.path;
  };

  systemd.services.garage.serviceConfig = {
    User = "garage";
    Group = "garage";
    DynamicUser = false;
    RestartSec = "1min";
    Restart = "always";
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
          --memory-limit $((1024*4)) \
          --stat-cache-ttl 10m \
          --cache mnt-cache \
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
        docker compose down
        docker compose up &
        # Wait for health check
        while ! curl -f http://localhost:2283 -o /dev/null; do
            sleep 1
        done

        # Tell systemd we're ready
        systemd-notify --ready
        wait
      '';
      preStop = "docker compose down";
      serviceConfig = {
        Type = "notify";
        WorkingDirectory = "/home/shogo/immich";
        Restart = "always";
        TimeoutSec = 600;
      };
      wantedBy = [ "default.target" ];
    };
  };
}
