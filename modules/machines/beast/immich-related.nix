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
        immich-backup-env = {
          file = flake-config.ageFile.immich-backup-env;
          mode = "0400";
          owner = "immich";
          group = "immich";
        };
        garage-secret = {
          file = flake-config.ageFile.garage-secret;
          mode = "0400";
          owner = "garage";
          group = "garage";
        };
      };

      users.users.immich = {
        name = "immich";
        isSystemUser = true;
        group = "immich";
        extraGroups = [ "docker" ];
      };
      users.groups.immich = { };

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
          after = [ "docker.socket" ];
          script = ''
            docker compose up
          '';
          preStop = ''
            docker compose down
          '';
          serviceConfig = {
            User = "immich";
            WorkingDirectory = "/immich";
            Restart = "always";
            TimeoutSec = 600;
            # CapabilityBoundingSet = "";
            PrivateDevices = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectProc = "invisible";
            ProcSubset = "pid";
            NoNewPrivileges = true;
            ProtectClock = true;
            SystemCallArchitectures = "native";
            RestrictNamespaces = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
            RestrictRealtime = true;
            MemoryDenyWriteExecute = true;
            ProtectHostname = true;
            ProtectHome = "read-only";
            SystemCallFilter = [
              "~@privileged"
              "~@debug"
              "~@cpu-emulation"
              "~@obsolete"
              "~@resources"
              "~@mount"
            ];
            RestrictAddressFamilies = "";
            RemoveIPC = true;
          };
          wantedBy = [ "default.target" ];
        };
        immich-backup = {
          script = ''
            aws s3 sync /immich/storage/ s3://immich/ \
              --endpoint http://localhost:3900 \
              --region garage \
              --cli-read-timeout 300
          '';
          path = [ pkgs.awscli2 ];
          serviceConfig = {
            Type = "oneshot";
            EnvironmentFile = config.age.secrets.immich-backup-env.path;
            ExecCondition = "systemctl is-active --quiet garage.service";
            User = "immich";
            CapabilityBoundingSet = "";
            PrivateDevices = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectProc = "invisible";
            ProcSubset = "pid";
            NoNewPrivileges = true;
            ProtectClock = true;
            SystemCallArchitectures = "native";
            RestrictNamespaces = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
            RestrictRealtime = true;
            MemoryDenyWriteExecute = true;
            ProtectHostname = true;
            ProtectHome = "read-only";
            SystemCallFilter = [
              "~@privileged"
              "~@debug"
              "~@cpu-emulation"
              "~@obsolete"
              "~@resources"
              "~@mount"
            ];
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
            RemoveIPC = true;
          };
        };
      };
      systemd.timers = {
        immich-backup = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            OnStartupSec = "1h";
            AccuracySec = "12h";
          };
        };
      };
      systemd.targets = {
        immich = {
          wantedBy = [ "default.target" ];
        };
      };
    };
}
