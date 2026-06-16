{ lib, ... }:
{
  options.sopsFile = lib.mkOption {
    description = "Files that contain sops-encrypted secrets";
    type = lib.types.attrsOf lib.types.path;
    default = { };
  };

  config.sopsFile = {
    common = ./common.yaml;
    garage-secret = ./garage-secret.yaml;
    immich-backup-env = ./immich-backup.yaml;
    niks3 = ./niks3.yaml;
  };
}
