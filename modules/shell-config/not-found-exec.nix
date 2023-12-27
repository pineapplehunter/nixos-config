{ config, lib, pkgs, ... }: with lib; let
  cfg = config.programs.zsh.not-found-exec;
  nix-bin = "${config.nix.package}/bin/nix";
in
{
  options = {
    programs.zsh.not-found-exec = {
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
      nixpkgs.url = mkOption {
        type = types.str;
        default = "nixpkgs/nixpkgs-unstable";
        description = ''
          The nixpkgs url to use.
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
    programs.command-not-found.enable = false;
    programs.zsh.interactiveShellInit = ''
      function command_not_found_handler() {
        not-found-exec-shell $@
      }
    '';

    environment.systemPackages = mkIf cfg.which-nix.enable [
      (pkgs.callPackage ./not-found-exec-shell.nix { inherit (cfg) nixpkgs confirm; })
      (pkgs.callPackage ./which-nix.nix { inherit (cfg) nixpkgs; })
    ];
  };
}



