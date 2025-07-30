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
      services.flatpak-update = {
        Unit.Description = "Update flatpak";
        Service.ExecStart = pkgs.writeShellScript "update-flatpak" ''
          if ! command -v flatpak > /dev/null; then
            echo flatpak not found. skipping.
            exit 0
          fi
          flatpak update --noninteractive -y
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
