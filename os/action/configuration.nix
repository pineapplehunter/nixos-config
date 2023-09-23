# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader.
  #boot.loader.grub.enable = true;
  #boot.loader.grub.useOSProber = true;
  #boot.loader.grub.device = "nodev";
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.binfmt.emulatedSystems = [ "aarch64-linux" "riscv64-linux" ];
  boot.loader.efi.efiSysMountPoint = "/efi";

  networking.hostName = "action"; # Define your hostname.
  #networking.networkmanager.enableStrongSwan = true;
  #services.xl2tpd.enable = true;
  #services.libreswan.enable = true;
  services.strongswan = {
    enable = true;
    secrets = [
      "ipsec.d/ipsec.nm-l2tp.secrets"
    ];
  };
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/" ];
  };
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # virtualisation.virtualbox.host.enable = true;
  # virtualisation.virtualbox.host.enableExtensionPack = true;
  # users.extraGroups.vboxusers.members = [ "shogo" ];
  # virtualisation.libvirtd.enable = true;
  # programs.dconf.enable = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Asia/Tokyo";

  # Select internationalisation properties.
  i18n.defaultLocale = "ja_JP.UTF-8";

  i18n.inputMethod = {
    enabled = "ibus";
    ibus.engines = with pkgs.ibus-engines; [ mozc anthy ];
  };

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ja_JP.UTF-8";
    LC_IDENTIFICATION = "ja_JP.UTF-8";
    LC_MEASUREMENT = "ja_JP.UTF-8";
    LC_MONETARY = "ja_JP.UTF-8";
    LC_NAME = "ja_JP.UTF-8";
    LC_NUMERIC = "ja_JP.UTF-8";
    LC_PAPER = "ja_JP.UTF-8";
    LC_TELEPHONE = "ja_JP.UTF-8";
    LC_TIME = "ja_JP.UTF-8";
  };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-emoji
    fira-code
    fira-code-symbols
    vistafonts
    (nerdfonts.override { fonts = [ "FiraCode" "DejaVuSansMono" ]; })
  ];
  fonts.fontDir.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  services.gnome.gnome-keyring.enable = true;
  # security.pam.services = {
  #   gdm.fprintAuth = false;
  #   login.fprintAuth = false;
  #   passwd.fprintAuth = false;
  # };
  security.pam.services.login.fprintAuth = false;
  security.pam.services.gdm-fingerprint = lib.mkIf (config.services.fprintd.enable) {
    text = ''
      auth       required                    pam_shells.so
      auth       requisite                   pam_nologin.so
      auth       requisite                   pam_faillock.so      preauth
      auth       required                    ${pkgs.fprintd}/lib/security/pam_fprintd.so
      auth       optional                    pam_permit.so
      auth       required                    pam_env.so
      auth       [success=ok default=1]      ${pkgs.gnome.gdm}/lib/security/pam_gdm.so
      auth       optional                    ${pkgs.gnome.gnome-keyring}/lib/security/pam_gnome_keyring.so

      account    include                     login

      password   required                    pam_deny.so

      session    include                     login
      session    optional                    ${pkgs.gnome.gnome-keyring}/lib/security/pam_gnome_keyring.so auto_start
    '';
  };

  services.snapper.configs = {
    home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ "shogo" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = "5";
      TIMELINE_LIMIT_DAILY = "6";
      TIMELINE_LIMIT_WEEKLY = "2";
      TIMELINE_LIMIT_MONTHLY = "3";
      TIMELINE_LIMIT_YEARLY = "1";
    };
  };

  # Configure keymap in X11
  services.xserver = {
    layout = "jp";
    xkbVariant = "";
  };

  # Configure console keymap
  console.keyMap = "jp106";

  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.avahi.enable = true;
  services.avahi.nssmdns = true;
  services.avahi.openFirewall = true;

  services.flatpak.enable = true;

  services.fprintd = {
    enable = true;
    tod.enable = true;
    tod.driver = pkgs.libfprint-2-tod1-goodix;
  };

  services.udev.packages = with pkgs; [ gnome.gnome-settings-daemon ];

  services.tailscale.enable = true;

  virtualisation = {
    docker.enable = true;
    #podman.enable = true;
  };
  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.defaultUserShell = pkgs.zsh;
  users.users = {
    shogo = {
      isNormalUser = true;
      description = "Shogo Takata";
      extraGroups = [ "networkmanager" "wheel" ];
      packages = with pkgs; [
        # firefox
        #  thunderbird
        jetbrains.idea-ultimate
      ];
      # shell = pkgs.nushell;
    };

    riken = {
      isNormalUser = true;
      description = "Shogo at Riken";
      extraGroups = [ "networkmanager" "wheel" ];
      # packages = with pkgs; [
      #   # firefox
      #   #  thunderbird
      # ];
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" "ca-derivations" ];
      trusted-users = [ "shogo" "riken" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    optimise.automatic = true;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # tools
    vim
    curl
    helix
    unzip
    git
    nix-index
    htop
    nethogs
    github-cli
    starship
    du-dust
    virt-manager
    btrfs-assistant
    ripgrep
    devenv
    nix-output-monitor
    gnome.gnome-tweaks
    nixd
    cachix
    (writeShellScriptBin "curl-http3" "exec -a $0 ${curl-http3}/bin/curl $@")
    # editor
    vscode
    jetbrains.idea-ultimate
    vivado
    # service
    syncthing
    webcord
    slack
    # lang
    rustup
    julia
    python3
    # other
    (writeShellScriptBin "flatpak-chrome-alias" "flatpak run com.google.Chrome $@")
    nixos-artwork-wallpaper
    udisks2
  ];

  environment.variables.EDITOR = "hx";

  programs.direnv = {
    enable = true;
    silent = true;
    nix-direnv = {
      enable = true;
      package = (pkgs.nix-direnv.overrideAttrs (old: {
        patches = [ ./direnv.patch ];
        postPatch = ''
          sed -i "2iNIX_BIN_PREFIX=${pkgs.nix}/bin/" direnvrc
          substituteInPlace direnvrc \
            --replace "grep" "${pkgs.gnugrep}/bin/grep"
          substituteInPlace direnvrc \
            --replace "nom" "${pkgs.nix-output-monitor}/bin/nom"
        '';
      }));
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
  programs.zsh = {
    enable = true;
    shellAliases = {
      ls = "${pkgs.eza}/bin/eza --icons";
      la = "ls -a";
    };
    ohMyZsh.enable = true;
    interactiveShellInit = ''
      eval "$(starship init zsh)"
    '';
  };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?

}
