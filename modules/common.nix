{ config, inputs, ... }:
let
  flake-config = config;
in
{
  flake.nixosModules.common =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      imports =
        let
          mods = flake-config.flake.nixosModules;
        in
        [
          inputs.agenix.nixosModules.default
          inputs.home-manager.nixosModules.home-manager
          inputs.howdy-module.nixosModules.default
          inputs.xremap-flake.nixosModules.default
          mods.fonts
          mods.gstreamer
          mods.hibernate
          mods.japanese
          mods.niri
          mods.nixos-artwork
          mods.packages
          mods.power-targets
          mods.shell-config
          mods.windows-vm
        ];

      pineapplehunter.japanese.enable = true;
      nixos-artwork.enable = lib.mkDefault true;

      nixpkgs = {
        overlays = [
          inputs.nixgl.overlays.default
          inputs.nix-xilinx.overlay
          inputs.agenix.overlays.default
          flake-config.flake.overlays.default
        ];
        config.allowUnfreePredicate =
          pkg:
          lib.elem (pkgs.lib.getName pkg) [
            "libfprint-2-tod1-goodix"
            "slack"
            "vscode"
            "zoom"
          ];
      };

      nix = {
        package = pkgs.nixVersions.latest;
        settings = {
          experimental-features = [
            "auto-allocate-uids"
            "blake3-hashes"
            "ca-derivations"
            "cgroups"
            "dynamic-derivations"
            "flakes"
            "nix-command"
            "no-url-literals"
            "parse-toml-timestamps"
            "pipe-operators"
            "recursive-nix"
          ];
          auto-allocate-uids = true;
          trusted-users = [ "@wheel" ];
          substituters = [
            "https://cache.nixos.org/"
            "https://attic.s.ihavenojob.work/shogo"
          ];
          trusted-public-keys = [
            "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            "shogo:R9ZWo9iGw8E0X6G24R7XLPH0UeE3VZ/WFi2+D0Kmud4="
          ];
          warn-dirty = false;
          allow-import-from-derivation = false;
          use-cgroups = true;
        };
        gc = {
          automatic = true;
          dates = "monthly";
          options = "--delete-older-than 30d";
          randomizedDelaySec = "1h";
        };
        optimise = {
          automatic = true;
          dates = "monthly";
          randomizedDelaySec = "1h";
        };
        extraOptions = ''
          !include ${config.age.secrets.access_tokens.path}
        '';
      };

      boot.plymouth.enable = lib.mkDefault true;
      boot.kernelPackages = pkgs.linuxPackages_latest;

      age = {
        secrets.access_tokens = {
          file = ../secrets/access-tokens.age;
          mode = "0440";
          group = "wheel";
        };
      };

      programs = {
        # Some programs need SUID wrappers, can be configured further or are
        # started in user sessions.
        # programs.mtr.enable = true;
        gnupg.agent = {
          enable = true;
          enableSSHSupport = true;
        };
        starship = {
          enable = true;
        };
        zsh = {
          enable = true;
          shellAliases = {
            ls = "${pkgs.eza}/bin/eza --icons --git --time-style '+%y/%m/%d %H:%M'";
            la = "${pkgs.eza}/bin/eza --icons --git --time-style '+%y/%m/%d %H:%M' --all";
            ll = "${pkgs.eza}/bin/eza --icons --git --time-style '+%y/%m/%d %H:%M' --all --long --header";
            ip = "ip --color=auto";
          };
        };
        not-found-exec.enable = true;
        which-nix.enable = true;
        sudo-nix.enable = true;
        man-nix.enable = true;

        zoom-us.enable = true;

        bandwhich.enable = true;
      };

      i18n.inputMethod = {
        enable = true;
        type = "ibus";
      };

      qt = {
        enable = true;
        platformTheme = "gnome";
        style = "adwaita";
      };

      services = {
        xremap.enable = lib.mkDefault false;

        # Enable the OpenSSH daemon.
        openssh = {
          enable = true;
          startWhenNeeded = true;
        };

        # Enable CUPS to print documents.
        printing = {
          enable = true;
          drivers = [
            pkgs.gutenprint
            pkgs.hplip
            pkgs.splix
            pkgs.epson-escpr
          ];
        };

        # Enable flatpak
        flatpak.enable = true;

        pipewire = {
          enable = true;
          alsa.enable = true;
          pulse.enable = true;
          # If you want to use JACK applications, uncomment this
          #jack.enable = true;

          # use the example session manager (no others are packaged yet so this is enabled by default,
          # no need to redefine it in your config for now)
          #media-session.enable = true;
        };

        avahi = {
          enable = lib.mkDefault true;
          nssmdns4 = true;
          openFirewall = true;
        };

        dbus.implementation = "broker";
      };

      users.defaultUserShell = pkgs.zsh;

      # Enable sound with pipewire.
      security.rtkit.enable = true;

      environment = {
        variables = {
          BAT_THEME = "GitHub";
          EDITOR = "hx";
        };
        enableAllTerminfo = true;
      };

      home-manager = {
        useGlobalPkgs = true;
        backupFileExtension = "hm-backup";
      };

      security.sudo-rs.enable = true;

      networking.nftables.enable = true;

      system.stateVersion = config.system.nixos.release;
    };
}
