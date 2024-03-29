{ pkgs, lib, config, ... }: {
  programs.helix = {
    enable = true;
    defaultEditor = true;
  };

  # system wide packages
  environment.systemPackages = (with pkgs; [
    # tools
    vim
    curl-http3
    unzipNLS
    git
    nix-index
    htop
    nethogs
    github-cli
    starship
    du-dust
    btrfs-assistant
    ripgrep
    nix-output-monitor
    gnome.gnome-tweaks
    nil
    cachix
    nixfmt
    nixpkgs-fmt
    tree
    fd
    zellij
    btop
    jq
    file
    binutils
    # editor
    vscode
    jetbrains.idea-ultimate
    vivado
    gnome.dconf-editor
    blender
    # service
    syncthing
    webcord
    slack
    # lang
    rustup
    julia
    python3
    stdenv.cc
    # other
    (writeShellScriptBin "flatpak-chrome-alias"
      "flatpak run com.google.Chrome $@")
    nixos-artwork-wallpaper
    udisks2
    gnome-firmware
    wineWowPackages.wayland
    winetricks
    ghidra
    jdk
    usbutils
    pciutils
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
    ]));
}
