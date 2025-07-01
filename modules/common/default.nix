{
  pkgs,
  config,
  self,
  inputs,
  lib,
  ...
}:
{
  imports =
    let
      inherit (self.nixosModules)
        shell-config
        japanese
        windows-vm
        gstreamer
        ;
      inherit (inputs)
        agenix
        xremap-flake
        home-manager
        howdy-module
        ;
    in
    [
      ./packages.nix
      ./fonts.nix
      shell-config
      japanese
      windows-vm
      gstreamer
      agenix.nixosModules.default
      howdy-module.nixosModules.default
      xremap-flake.nixosModules.default
      home-manager.nixosModules.home-manager
    ];

  pineapplehunter.japanese.enable = true;

  nixpkgs = {
    overlays = [
      inputs.nixgl.overlays.default
      inputs.nix-xilinx.overlay
      inputs.agenix.overlays.default
      self.overlays.default
    ];
    config.allowUnfreePredicate =
      pkg:
      lib.elem (pkgs.lib.getName pkg) [
        "libfprint-2-tod1-goodix"
        "slack"
        "vista-fonts"
        "vscode"
      ];
  };

  nix = {
    package = pkgs.nixVersions.latest;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
        "ca-derivations"
        "auto-allocate-uids"
      ];
      auto-allocate-uids = true;
      trusted-users =
        let
          normalUsers = lib.filterAttrs (_: user: user.isNormalUser) config.users.users;
          normalUserNames = lib.attrNames normalUsers;
        in
        normalUserNames;
      substituters = [
        "https://cache.nixos.org/"
        "https://attic.s.ihavenojob.work/shogo"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "shogo:dzOG75ufKKljdUzTbGDpTuBmup3/K5RDmr28jb0jHCg="
      ];
      warn-dirty = false;
      auto-optimise-store = true;
      allow-import-from-derivation = false;
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
      file = ../../secrets/access-tokens.age;
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
        la = "ls -a";
        ll = "ls -lha";
        ip = "ip -c";
      };
    };
    not-found-exec.enable = true;
    which-nix.enable = true;
    sudo-nix.enable = true;
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
    openssh.enable = true;

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
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

  };

  users.defaultUserShell = pkgs.zsh;

  systemd.services.NetworkManager-wait-online.enable = false;

  # Enable sound with pipewire.
  security.rtkit.enable = true;

  environment.variables = {
    BAT_THEME = "GitHub";
    EDITOR = "hx";
  };

  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "hm-backup";
    extraSpecialArgs = {
      inherit inputs self;
    };
  };

  security.sudo-rs.enable = true;

  system.stateVersion = config.system.nixos.release;
}
