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
            local cmd="$1"
            shift

            if [[ $cmd = *@* ]]; then
              local cmd_no_at=''\${''\${(s/@/)cmd}[1]}
              local cmd_package=''\${''\${(s/@/)cmd}[2]}
              ${optionalString cfg.confirm ''echo "Command '$cmd' not found, do you want to try $cmd_no_at from ${cfg.nixpkgs.url}#$cmd_package? [y/N]: "''}
            else
              ${optionalString cfg.confirm ''echo "Command '$cmd' not found, do you want to try $cmd from ${cfg.nixpkgs.url}? [y/N]: "''}
            fi

            ${optionalString cfg.confirm ''if read -q; then''}
            if [[ $cmd = *@* ]]; then
              local cmd_no_at=''\${''\${(s/@/)cmd}[1]}
              local cmd_package=''\${''\${(s/@/)cmd}[2]}
              ${nix-bin} shell "${cfg.nixpkgs.url}#$cmd_package" -c $cmd_no_at $*
            else
              ${nix-bin} shell "${cfg.nixpkgs.url}#$cmd" -c $cmd $*
            fi
            ${optionalString cfg.confirm ''fi''}
          }
        '';

        environment.systemPackages = mkIf cfg.which-nix.enable [ 
          (pkgs.writeShellScriptBin "which-nix" ''
            #!${pkgs.stdenv.shell}
            export cmd="$1"
            if [[ $cmd = *@* ]]; then
              export cmd_no_at=''\${''\${(s/@/)cmd}[1]}
              export cmd_package=''\${''\${(s/@/)cmd}[2]}
              echo ''\${${nix-bin} path-info "${cfg.nixpkgs.url}#$cmd_package" 2> /dev/null}/bin/$cmd_no_at
            else
              echo ''\${${nix-bin} path-info "${cfg.nixpkgs.url}#$cmd" 2> /dev/null}/bin/$cmd
            fi
          '')
         ];
      };
}




