{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.programs.not-found-exec;
in
{
  options = {
    programs.not-found-exec = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable the not-found-exec plugin.
        '';
      };
      confirm = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Confirm before running the command.
        '';
      };
      which-nix.enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable the which-nix function.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    programs = {
      command-not-found.enable = false;

      zsh.interactiveShellInit = ''
        function command_not_found_handler() {
          not-found-exec-shell $@
        }
      '';
      fish.interactiveShellInit = ''
        function fish_command_not_found
          not-found-exec-shell $argv
        end
      '';
      bash.interactiveShellInit = ''
        function command_not_found_handler() {
            not-found-exec-shell $@
          }
      '';
    };

    environment.systemPackages = mkIf cfg.which-nix.enable [
      (pkgs.callPackage ./not-found-exec-shell.nix { inherit (cfg) confirm; })
      (pkgs.callPackage ./which-nix.nix { })
      (pkgs.callPackage ./sudo-nix.nix { })
    ];
  };
}
