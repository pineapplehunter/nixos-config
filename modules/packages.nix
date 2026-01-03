{
  flake.nixosModules.packages =
    { pkgs, ... }:
    {
      # system wide packages
      environment.systemPackages = with pkgs; [
        # tools
        atop
        binutils
        btop
        btrfs-assistant
        curlFull
        fd
        file
        git
        github-cli
        gnome-tweaks
        gnumake
        google-calendar-open
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
        # https://github.com/NixOS/nixpkgs/pull/472294
        # omnix
        openssl
        papers
        pciutils
        reptyr
        ripgrep
        snapper-gui
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
        # super-productivity

        # other
        gnome-firmware
        man-pages
        # orca-slicer
        udisks2
        nautilus-open-any-terminal
        nautilus-python
      ];

      environment.gnome.excludePackages = [ pkgs.evince ];
    };
}
