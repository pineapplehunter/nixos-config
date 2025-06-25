{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    getExe
    mkEnableOption
    mkIf
    optionals
    ;

  cfg = config.programs;

  not-found-exec = pkgs.replaceVarsWith {
    src = ./not-found-exec.sh;
    replacements = {
      confirm = cfg.not-found-exec.confirm;
      cut = "${pkgs.coreutils}/bin/cut";
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
    replacements.which-nix = getExe which-nix;
    name = "sudo-nix";
    dir = "bin";
    isExecutable = true;
    meta.mainProgram = "sudo-nix";
  };
in
{
  options = {
    programs = {
      not-found-exec = {
        enable = mkEnableOption "not-found-exec plugin";
        confirm = mkEnableOption "Confirm before running the command";
        addToPath = mkEnableOption "add to path";
      };
      which-nix.enable = mkEnableOption "which-nix program";
      sudo-nix.enable = mkEnableOption "sudo-nix program";
    };
  };

  config = mkIf cfg.not-found-exec.enable {
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

    environment.systemPackages =
      optionals cfg.not-found-exec.addToPath [ not-found-exec ]
      ++ optionals cfg.which-nix.enable [ which-nix ]
      ++ optionals cfg.sudo-nix.enable [ sudo-nix ];
  };
}
