{
  config,
  lib,
  ...
}:
let
  cfg = config.pineapplehunter;
  inherit (lib)
    mkOption
    mkIf
    types
    mkEnableOption
    mkMerge
    ;
in
{
  options.pineapplehunter = {
    config-name = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "name of the configuration in flake";
    };
    isNixos = mkEnableOption "remove nixGL wrapper";
  };
  config.home.sessionVariables = mkMerge [
    (mkIf (cfg.config-name != null) {
      HOME_CONFIG_NAME = cfg.config-name;
    })
  ];
}
