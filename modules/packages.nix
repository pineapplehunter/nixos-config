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
        delta
        fd
        file
        fsverity-utils
        git
        github-cli
        glow
        gnome-tweaks
        gnumake
        google-calendar-open
        helix
        htop
        ima-evm-utils
        jq
        lsof
        ncdu
        nethogs
        nix-output-monitor
        nix-tree
        nixfmt
        npins
        omnix
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
        super-productivity

        # other
        gnome-firmware
        man-pages
        man-pages-posix
        # orca-slicer
        udisks2
        nautilus-open-any-terminal
        nautilus-python
      ];
    };
}
