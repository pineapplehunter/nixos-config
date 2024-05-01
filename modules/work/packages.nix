{ pkgs, lib, config, ... }: {
  environment.systemPackages = (with pkgs; [
    webcord
    slack
    super-productivity
  ]) ++
  # gnome-extensions
  (lib.optionals config.services.xserver.desktopManager.gnome.enable
    (with pkgs.gnomeExtensions; [
      tailscale-status
      runcat
      caffeine
      appindicator
      just-perfection
      syncthing-indicator
      tiling-assistant
    ]));
}
