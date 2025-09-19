{
  pkgs,
  config,
  lib,
  ...
}:

let
  inherit (lib)
    concatStringsSep
    mkEnableOption
    mkMerge
    mkOption
    ;
  inherit (lib.types) listOf str submodule;
in
{
  options.services = {
    flatpak-repo = {
      enable = mkEnableOption "Add flathub repo to user";
      repos = mkOption {
        description = "repositories to add";
        type = listOf (submodule {
          options = {
            name = mkOption { type = str; };
            repo = mkOption { type = str; };
          };
        });
        default = [
          {
            name = "flathub";
            repo = "https://dl.flathub.org/repo/flathub.flatpakrepo";
          }
        ];
      };
    };
    flatpak-update.enable = mkEnableOption "flatpak update service";
  };

  config.systemd.user = mkMerge [
    (lib.optionalAttrs config.services.flatpak-repo.enable {
      # initialize flathub for system
      # https://wiki.nixos.org/wiki/Flatpak
      services.flatpak-repo = {
        Unit.Description = "Add flathub repo to user";
        Service.ExecStart = pkgs.writeShellScript "flatpak-add-repo" ''
          # add nixos bin path
          PATH=$PATH:/run/current-system/sw/bin
          if ! command -v flatpak > /dev/null; then
            echo flatpak not found. skipping.
            exit 0
          fi
          ${concatStringsSep "\n" (
            map (
              { name, repo }: "flatpak remote-add --user --if-not-exists ${name} ${repo}"
            ) config.services.flatpak-repo.repos
          )}
        '';
        Install.WantedBy = [ "default.target" ];
      };
    })
    (lib.optionalAttrs config.services.flatpak-update.enable {
      services.flatpak-update = {
        Unit.Description = "Update flatpak";
        Service.ExecStart = pkgs.writeShellScript "update-flatpak" ''
          # add nixos bin path
          PATH=$PATH:/run/current-system/sw/bin
          if ! command -v flatpak > /dev/null; then
            echo flatpak not found. skipping.
            exit 0
          fi
          flatpak update --user --noninteractive -y
        '';
      };

      timers.flatpak-update = {
        Unit.Description = "Timer for periodic flatpak updates";
        Timer = {
          OnCalendar = "daily";
          AccuracySec = "12h";
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })
  ];
}
