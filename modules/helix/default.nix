{ config, lib, pkgs, ... }:
with lib;
let cfg = config.programs.helix;
in {
  options = {
    programs.helix = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable helix";
      };
      package = mkOption {
        type = types.package;
        default = pkgs.helix;
        description = "The helix package";
      };
      defaultEditor = mkOption {
        type = types.bool;
        default = false;
        description = "Make helix the default editor";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    environment.variables.EDITOR = mkIf cfg.defaultEditor (mkOverride 900 "hx");
  };
}
