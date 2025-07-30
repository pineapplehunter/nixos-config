{
  pkgs,
  config,
  lib,
  ...
}:

let
  inherit (lib) mkIf mkEnableOption;
  cfg = config.services.flatpak-update;
in
{
  options.services.flatpak-update.enable = mkEnableOption "flatpak update service";

  config = mkIf cfg.enable {
    systemd.user = {
      # initialize flathub for system
      # https://wiki.nixos.org/wiki/Flatpak
      services.flatpak-repo = {
        Unit.Description = "Add flathub repo to user";
        Service.ExecStart = pkgs.writeShellScript "flatpak-add-repo" ''
          if ! command -v flatpak > /dev/null; then
            echo flatpak not found. skipping.
            exit 0
          fi
          flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        '';
        Install.WantedBy = [ "default.target" ];
      };

      services.flatpak-update = {
        Unit.Description = "Update flatpak";
        Service.ExecStart = pkgs.writeShellScript "update-flatpak" ''
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
    };
  };
}
