{ config, pkgs, ... }: {
  # system wide packages
  environment.systemPackages = with pkgs;[
    # tools
    vim
    curl
    helix
    unzip
    git
    nix-index
    htop
    nethogs
    github-cli
    starship
    du-dust
    virt-manager
    btrfs-assistant
    ripgrep
    devenv
    nix-output-monitor
    gnome.gnome-tweaks
    nixd
    cachix
    nixpkgs-fmt
    tree
    (writeShellScriptBin "curl-http3" "exec -a $0 ${curl-http3}/bin/curl $@")
    # editor
    vscode
    jetbrains.idea-ultimate
    vivado
    # service
    syncthing
    webcord
    slack
    # lang
    rustup
    julia
    python3
    # other
    (writeShellScriptBin "flatpak-chrome-alias" "flatpak run com.google.Chrome $@")
    nixos-artwork-wallpaper
    udisks2
    gnome-firmware
    wineWowPackages.waylandFull
    winetricks
  ];
  environment.variables.EDITOR = "hx";
}