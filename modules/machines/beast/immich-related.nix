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
      sops = {
        secrets = {
          immich-backup-access-key-id = {
            sopsFile = flake-config.sopsFile.immich-backup-env;
            key = "access-key-id";
          };
          immich-backup-secret-access-key = {
            sopsFile = flake-config.sopsFile.immich-backup-env;
            key = "secret-access-key";
          };
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
        templates."immich-backup-aws-config" = {
          content = ''
            [default]
            aws_access_key_id=${config.sops.placeholder.immich-backup-access-key-id}
            aws_secret_access_key=${config.sops.placeholder.immich-backup-secret-access-key}
            region=garage
          '';
          mode = "0400";
          owner = "immich";
          group = "immich";
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
        settings = lib.mkMerge [
          (lib.importTOML ./garage-config.toml)
          {
            rpc_secret_file = config.sops.secrets.garage-rpc-secret.path;
            admin.admin_token_file = config.sops.secrets.garage-admin-token.path;
          }
        ];
      };

      systemd.services.garage = {
        serviceConfig = {
          User = "garage";
          Group = "garage";
          DynamicUser = false;
          RestartSec = "1min";
          Restart = "always";
        };
        environment = {
          # I only allow access to the key for garage group
          GARAGE_ALLOW_WORLD_READABLE_SECRETS = "true";
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
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
            RemoveIPC = true;
          };
          wantedBy = [ "default.target" ];
        };
        immich-backup = {
          script = ''
            aws s3 sync /immich/storage/ s3://immich/ \
              --endpoint http://localhost:3900 \
              --region garage \
              --cli-read-timeout 300 \
              --no-progress
          '';
          restartIfChanged = false;
          path = [ pkgs.awscli2 ];
          environment = {
            AWS_CONFIG_FILE = config.sops.templates.immich-backup-aws-config.path;
          };
          serviceConfig = {
            Type = "oneshot";
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
