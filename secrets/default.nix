{ lib, ... }:
{
  options.sopsFile = lib.mkOption {
    description = "Files that contain sops-encrypted secrets";
    type = lib.types.attrsOf lib.types.path;
    default = { };
  };

  config.sopsFile = {
    common = ./common.yaml;
    garage-secret = ./garage-secret.env;
    immich-backup-env = ./immich-backup.env;
  };
}
