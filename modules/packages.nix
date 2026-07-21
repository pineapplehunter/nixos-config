{
  flake.nixosModules.packages =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.my.common-packages.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable common system packages";
      };

      config.environment.systemPackages = lib.mkIf config.my.common-packages.enable (
        with pkgs;
        [
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
        ]
      );
    };
}
