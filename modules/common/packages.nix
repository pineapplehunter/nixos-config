{ pkgs, ... }:
{
  # system wide packages
  environment.systemPackages = with pkgs; [
    # tools
    age
    agenix
    atop
    binutils
    btop
    btrfs-assistant
    curl-http3
    fd
    file
    git
    github-cli
    gnome-tweaks
    gnumake
    helix
    htop
    jq
    ncdu
    nethogs
    nix-index
    nix-output-monitor
    nix-tree
    nixfmt-rfc-style
    nixpkgs-fmt
    npins
    openssl
    papers
    pciutils
    reptyr
    ripgrep
    tree
    unzipNLS
    usbutils
    vim
    wl-clipboard

    # editor
    dconf-editor
    vscode

    # lang
    python3

    # office
    errands
    gitify
    pdfarranger
    slack
    super-productivity
    webcord

    # other
    gnome-firmware
    man-pages
    orca-slicer
    udisks2
    nautilus-open-any-terminal
    nautilus-python
  ];

  environment.gnome.excludePackages = [ pkgs.evince ];
}
