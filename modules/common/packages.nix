{ pkgs, ... }:
let
  ventoy-custom = pkgs.ventoy-full.override {
    defaultGuiType = "gtk3";
    withGtk3 = true;
  };
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
    pkgs.reptyr
    pkgs.ripgrep
    pkgs.sops
    pkgs.tree
    pkgs.unzipNLS
    pkgs.vim
    pkgs.wl-clipboard

    # editor
    pkgs.dconf-editor
    pkgs.vscode

    # lang
    pkgs.python3

    # other
    pkgs.gitify
    pkgs.gnome-firmware
    pkgs.man-pages
    pkgs.openssl
    pkgs.papers
    pkgs.pciutils
    pkgs.stdenv.cc
    pkgs.super-productivity
    pkgs.udisks2
    pkgs.usbutils

    cachix-no-man
    ventoy-custom
  ];

  environment.gnome.excludePackages = [ pkgs.evince ];
}
