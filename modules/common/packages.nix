{ pkgs, ... }:
{
  # system wide packages
  environment.systemPackages = builtins.attrValues {
    inherit (pkgs)
      # tools
      vim
      unzipNLS
      git
      nix-index
      htop
      nethogs
      github-cli
      du-dust
      btrfs-assistant
      ripgrep
      nix-output-monitor
      gnome-tweaks
      nixpkgs-fmt
      nixfmt-rfc-style
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
      # editor
      vscode
      dconf-editor
      # lang
      python3
      # other
      udisks2
      gnome-firmware
      usbutils
      pciutils
      papers
      openssl
      gitify
      ;
    ventoy-custom = (
      pkgs.ventoy-full.override {
        defaultGuiType = "gtk3";
        withGtk3 = true;
      }
    );
    cachix-no-man = (
      pkgs.symlinkJoin {
        name = "cachix";
        version = pkgs.cachix.version;
        paths = [ pkgs.cachix.bin ];
      }
    );
    inherit (pkgs.stdenv) cc;
  };

  environment.gnome.excludePackages = [ pkgs.evince ];
}
