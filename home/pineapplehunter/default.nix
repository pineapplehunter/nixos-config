{ config
, lib
, ...
}:
let
  cfg = config.pineapplehunter;
  inherit (lib) mkOption mkIf types;
in
{
  options.pineapplehunter.config-name = mkOption {
    type = types.nullOr types.str;
    default = null;
    description =
      "name of the configuration in flake";
  };
  config.home.sessionVariables = mkIf (cfg.config-name != null) {
    HOME_CONFIG_NAME = cfg.config-name;
  };
}
