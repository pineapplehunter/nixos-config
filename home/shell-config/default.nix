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

      not-found-exec = pkgs.replaceVarsWith {
        src = ./not-found-exec.sh;
        replacements = {
          inherit (cfg.not-found-exec) confirm;
          cut = "${pkgs.coreutils}/bin/cut";
          jq = getExe pkgs.jq;
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

      man-nix = pkgs.replaceVarsWith {
        src = ./man-nix.sh;
        replacements = {
          jq = getExe pkgs.jq;
          man = getExe pkgs.man;
        };
        name = "man-nix";
        dir = "bin";
        isExecutable = true;
        meta.mainProgram = "man-nix";
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
