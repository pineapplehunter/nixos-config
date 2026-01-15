{ lib, ... }:
{
  options.ageFile = lib.mkOption {
    description = "Files that contain age secrets";
    type = lib.types.attrsOf lib.types.path;
    default = { };
  };

  config.ageFile = {
    access-tokens = ./access-tokens.age;
    garage-secret = ./garage-secret.age;
    immich-backup-env = ./immich-backup-env.age;
  };
}
