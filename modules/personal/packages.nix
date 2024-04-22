{ pkgs, lib, config, ... }: {
  environment.systemPackages = (with pkgs; [
    tectonic
    blender
    syncthing
    webcord
    slack
    curl-http3
    jujutsu
    vivado
    jetbrains.idea-ultimate
    (writeShellScriptBin "flatpak-chrome-alias"
      "flatpak run com.google.Chrome $@")
    nixos-artwork-wallpaper
    ghidra
    wineWow64Packages.wayland
    winetricks
    jdk
    super-productivity
    android-studio
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
    ]));
}
