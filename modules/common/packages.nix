{ pkgs, ... }:
let
  cachix-no-man = pkgs.symlinkJoin {
    inherit (pkgs.cachix) version;
    name = "cachix";
    paths = [ pkgs.cachix.bin ];
  };
in
{
  # system wide packages
  environment.systemPackages = [
    # tools
    cachix-no-man
    pkgs.atop
    pkgs.binutils
    pkgs.btop
    pkgs.btrfs-assistant
    pkgs.curl-http3
    pkgs.fd
    pkgs.file
    pkgs.git
    pkgs.github-cli
    pkgs.gnome-tweaks
    pkgs.gnumake
    pkgs.htop
    pkgs.jq
    pkgs.ncdu
    pkgs.nethogs
    pkgs.niv
    pkgs.nix-index
    pkgs.nix-output-monitor
    pkgs.nix-tree
    pkgs.nixfmt-rfc-style
    pkgs.nixpkgs-fmt
    pkgs.npins
    pkgs.openssl
    pkgs.papers
    pkgs.pciutils
    pkgs.reptyr
    pkgs.ripgrep
    pkgs.sops
    pkgs.tree
    pkgs.unzipNLS
    pkgs.usbutils
    pkgs.vim
    pkgs.wl-clipboard

    # editor
    pkgs.dconf-editor
    pkgs.vscode

    # lang
    pkgs.python3

    # office
    pkgs.errands
    pkgs.gitify
    pkgs.pdfarranger
    pkgs.slack
    pkgs.super-productivity
    pkgs.webcord

    # other
    pkgs.gnome-firmware
    pkgs.man-pages
    pkgs.udisks2
  ];

  environment.gnome.excludePackages = [ pkgs.evince ];
}
