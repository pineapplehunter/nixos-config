{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.programs.not-found-exec;

  not-found-exec = pkgs.replaceVarsWith {
    src = ./not-found-exec.sh;
    replacements = {
      shell = pkgs.stdenv.shell;
      confirm = cfg.confirm;
      cat = "${pkgs.coreutils}/bin/cat";
      jq = getExe pkgs.jq;
      nix = getExe config.nix.package;
    };
    name = "not-found-exec";
    dir = "bin";
    isExecutable = true;
    meta.mainProgram = "not-found-exec";
  };

  which-nix = pkgs.replaceVarsWith {
    src = ./which-nix.sh;
    replacements = {
      shell = pkgs.stdenv.shell;
      cat = "${pkgs.coreutils}/bin/cat";
      jq = getExe pkgs.jq;
      nix = getExe config.nix.package;
      which = getExe pkgs.which;
    };
    name = "which-nix";
    dir = "bin";
    isExecutable = true;
    meta.mainProgram = "which-nix";
  };

  sudo-nix = pkgs.replaceVarsWith {
    src = ./sudo-nix.sh;
    replacements = {
      shell = pkgs.stdenv.shell;
      which-nix = getExe which-nix;
    };
    name = "sudo-nix";
    dir = "bin";
    isExecutable = true;
    meta.mainProgram = "sudo-nix";
  };
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
          ${getExe not-found-exec} "$@"
        }
      '';
      fish.interactiveShellInit = ''
        function fish_command_not_found
          ${getExe not-found-exec} argv
        end
      '';
      bash.interactiveShellInit = ''
        function command_not_found_handler() {
          ${getExe not-found-exec} "$@"
        }
      '';
    };

    environment.systemPackages = mkIf cfg.which-nix.enable [
      which-nix
      sudo-nix
    ];
  };
}
