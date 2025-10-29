{ lib, ... }:
{
  options.ageFile = lib.mkOption {
    description = "Files that contain age secrets";
    type = lib.types.attrsOf lib.types.path;
    default = { };
  };

  config.ageFile = {
    access-tokens = ./access-tokens.age;
    geesefs-creds = ./geesefs-creds.age;
    garage-secret = ./garage-secret.age;
  };
}
