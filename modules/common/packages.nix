{ pkgs, ... }: {

  # system wide packages
  environment.systemPackages = with pkgs; [
    # tools
    vim
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
    (symlinkJoin { name = "cachix"; version = cachix.version; paths = [ cachix.bin ]; })
    nixpkgs-fmt
    tree
    fd
    btop
    jq
    file
    wl-clipboard
    binutils
    nix-tree
    sops
    gnumake
    ncdu
    niv
    npins
    alacritty
    # editor
    vscode
    gnome.dconf-editor
    # lang
    julia
    rustup
    python3
    stdenv.cc
    # other
    udisks2
    gnome-firmware
    usbutils
    pciutils
    papers
  ];

  environment.gnome.excludePackages = [ pkgs.gnome.evince ];
}
