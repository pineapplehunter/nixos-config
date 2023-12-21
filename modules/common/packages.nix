{ pkgs, ... }: {
  programs.helix = {
    enable = true;
    defaultEditor = true;
  };

  # system wide packages
  environment.systemPackages = with pkgs;[
    # tools
    vim
    curl
    unzip
    git
    nix-index
    htop
    nethogs
    github-cli
    starship
    du-dust
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
    fd
    (writeShellScriptBin "curl-http3" "exec -a $0 ${curl-http3}/bin/curl $@")
    zellij
    btop
    jq
    file
    # editor
    vscode
    (jetbrains.plugins.addPlugins jetbrains.idea-ultimate [ "github-copilot" ])
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
    snapper-gui
    ghidra
  ];
}
