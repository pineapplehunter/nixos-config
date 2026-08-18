{ config, ... }:
let
  flake-config = config;
in
{
  flake.nixosModules.beast-immich-related =
    {
      pkgs,
      config,
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

      users = {
        users.immich = {
          name = "immich";
          isSystemUser = true;
          group = "immich";
          extraGroups = [ "docker" ];
        };
        groups.immich = { };
      };

      networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 2283 ];

      systemd = {
        services = {
          # to startup immich at boot
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
              mkdir -p /tmp/immich-database
              cleanup () {
                rm -rf /tmp/immich-database
                restic unlock
              }
              trap cleanup EXIT

              echo Backing up database sql files
              echo Uncompressing database backups into /tmp/immich-database
              for file in /immich/storage/backups/*.sql.gz; do
                filename=$(basename "$file" .gz)
                gunzip -c "$file" > "/tmp/immich-database/$filename"
                restic backup "/tmp/immich-database/$filename" \
                  --skip-if-unchanged \
                  --tag auto,database \
                  --time "$(date -r "$file" '+%Y-%m-%d %H:%M:%S')"
              done

              rm -rf /tmp/immich-database

              echo Backing up immich data
              restic backup /immich/storage \
                --exclude /immich/storage/backups \
                --exclude /immich/storage/encoded-video \
                --exclude /immich/storage/thumbs \
                --tag auto,immich

              echo Checking backup integrity
              restic check

              echo Cleaning backups
              restic forget \
                --keep-daily 7 \
                --keep-monthly 12 \
                --prune \
                --tag auto \
                --group-by tags
            '';
            restartIfChanged = false;
            path = [
              pkgs.restic
              pkgs.gzip
            ];
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
              PrivateTmp = true;
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
        paths.immich-backup = {
          description = "Run immich backup when db backups are created";
          wantedBy = [ "default.target" ];
          pathConfig = {
            PathChanged = "/immich/storage/backups";
          };
        };
        targets.immich = {
          wantedBy = [ "default.target" ];
        };
      };
    };
}
