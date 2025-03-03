{ pkgs, ... }:
{
  # system wide packages
  environment.systemPackages = builtins.attrValues {
    inherit (pkgs)
      # tools
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
      htop
      jq
      ncdu
      nethogs
      niv
      nix-index
      nix-output-monitor
      nix-tree
      nixfmt-rfc-style
      nixpkgs-fmt
      npins
      reptyr
      ripgrep
      sops
      tree
      unzipNLS
      vim
      wl-clipboard

      # editor
      dconf-editor
      vscode

      # lang
      python3

      # other
      gitify
      gnome-firmware
      man-pages
      openssl
      papers
      pciutils
      super-productivity
      udisks2
      usbutils
      ;
    ventoy-custom = pkgs.ventoy-full.override {
      defaultGuiType = "gtk3";
      withGtk3 = true;
    };
    cachix-no-man = pkgs.symlinkJoin {
      inherit (pkgs.cachix) version;
      name = "cachix";
      paths = [ pkgs.cachix.bin ];
    };
    inherit (pkgs.stdenv) cc;
  };

  environment.gnome.excludePackages = [ pkgs.evince ];
}
