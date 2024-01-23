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
    binutils
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
    wineWowPackages.stable
    wineWowPackages.wayland
    winetricks
    snapper-gui
    ghidra
  ];
}
