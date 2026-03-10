{
  flake.homeModules.shell-config =
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

      not-found-exec = pkgs.writeShellApplication {
        name = "not-found-exec";
        runtimeInputs = [
          pkgs.jq
          pkgs.coreutils
        ];
        runtimeEnv = {
          CONFIRM = cfg.not-found-exec.confirm;
        };
        text = lib.readFile ./not-found-exec.sh;
      };

      which-nix = pkgs.writeShellApplication {
        name = "which-nix";
        runtimeInputs = [
          pkgs.jq
          pkgs.which
          pkgs.coreutils
        ];
        text = lib.readFile ./which-nix.sh;
      };

      sudo-nix = pkgs.writeShellApplication {
        name = "sudo-nix";
        runtimeInputs = [ which-nix ];
        text = lib.readFile ./sudo-nix.sh;
      };

      man-nix = pkgs.writeShellApplication {
        name = "man-nix";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          pkgs.man
        ];
        text = lib.readFile ./man-nix.sh;
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
          man-nix.enable = mkEnableOption "man-nix program";
        };
      };

      config = mkIf cfg.not-found-exec.enable {
        programs = {
          command-not-found.enable = false;

          zsh.initContent = ''
            command_not_found_handler() {
              "${getExe not-found-exec}" "$@"
            }
          '';
          fish.interactiveShellInit = ''
            function fish_command_not_found
              "${getExe not-found-exec}" $argv
            end
          '';
          bash.initExtra = ''
            command_not_found_handler() {
              "${getExe not-found-exec}" "$@"
            }
          '';
        };

        home.packages =
          optionals cfg.not-found-exec.addToPath [ not-found-exec ]
          ++ optionals cfg.which-nix.enable [ which-nix ]
          ++ optionals cfg.sudo-nix.enable [ sudo-nix ]
          ++ optionals cfg.man-nix.enable [ man-nix ];
      };
    };
}
