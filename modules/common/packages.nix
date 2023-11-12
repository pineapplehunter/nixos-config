{ pkgs, ... }: {
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
    rnix-lsp
    nil
    cachix
    nixpkgs-fmt
    tree
    (writeShellScriptBin "curl-http3" "exec -a $0 ${curl-http3}/bin/curl $@")
    zellij
    # editor
    vscode
    jetbrains.idea-ultimate
    vivado
    gnome.dconf-editor
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
    wineWowPackages.staging
    winetricks
    auto-cpufreq
  ];
  environment.variables.EDITOR = "hx";
}
