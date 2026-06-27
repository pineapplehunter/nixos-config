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
          immich-backup-restic-password = {
            sopsFile = flake-config.sopsFile.immich-backup-env;
            key = "restic-password";
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
            restic backup -v /immich/storage --tag auto
            restic forget -v --keep-last 30 --prune --tag auto
          '';
          restartIfChanged = false;
          path = [ pkgs.restic ];
          environment = {
            AWS_SHARED_CREDENTIALS_FILE = "%d/aws-credentials";
            RESTIC_PASSWORD_FILE = "%d/restic-password";
            RESTIC_REPOSITORY = "s3:http://localhost:3900/immich-backup";
            XDG_CACHE_HOME = "%C/immich-backup";
          };
          serviceConfig = {
            CacheDirectory = "immich-backup";
            CapabilityBoundingSet = "";
            DynamicUser = true;
            ExecCondition = "systemctl is-active --quiet garage.service";
            IOSchedulingClass = "best-effort";
            IOSchedulingPriority = 7;
            LoadCredential = [
              "aws-credentials:${config.sops.templates.immich-backup-aws-config.path}"
              "restic-password:${config.sops.secrets.immich-backup-restic-password.path}"
            ];
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            Nice = 10;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateUsers = true;
            ProcSubset = "pid";
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            RemoveIPC = true;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = [
              "~@privileged"
              "~@debug"
              "~@cpu-emulation"
              "~@obsolete"
              "~@resources"
              "~@mount"
            ];
            Type = "oneshot";
            UMask = "0077";
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
