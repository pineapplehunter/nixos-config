# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  lib,
  self,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        system = "x86_64-linux";
        maxJobs = 40;
        supportedFeatures = [
          "big-parallel"
          "kvm"
          "benchmark"
          "nixos-test"
        ];
        sshUser = "cbat";
        hostName = "100.98.144.77";
        speedFactor = 2;
      }
    ];
    settings = {
      connect-timeout = 10;
      builders-use-substitutes = true;
    };
    # channel.enable = false;
  };

  # Bootloader.
  boot = {
    loader.grub = {
      enable = true;
      useOSProber = true;
      efiSupport = true;
      device = "nodev";
      configurationLimit = 20;
      default = "saved";
      extraEntries = lib.mkAfter ''
        menuentry "System shutdown" {
        	echo "System shutting down..."
        	halt
        }
        menuentry "System restart" {
        	echo "System rebooting..."
        	reboot
        }
        if [ ''${grub_platform} == "efi" ]; then
        	menuentry 'UEFI Firmware Settings' --id 'uefi-firmware' {
        		fwsetup
        	}
        fi
      '';
    };
    loader.efi.canTouchEfiVariables = true;
    binfmt.emulatedSystems = [ "aarch64-linux" ];
  };

  # https://discourse.nixos.org/t/suspend-then-hibernate/31953/5
  powerManagement.enable = true;
  powerManagement.powertop.enable = true;
  services.thermald.enable = true;

  systemd.services.docker.enable = false;
  systemd.sockets.docker.enable = false;

  services = {
    xremap = {
      enable = true;
      withGnome = true;
      config.modmap = [
        {
          name = "caps-esc";
          remap = {
            "CapsLock" = "Esc";
          };
        }
      ];
    };
    btrfs.autoScrub = {
      enable = true;
      fileSystems = [ "/" ];
    };
    xserver = {
      # Enable the X11 windowing system.
      enable = true;

      # Enable the GNOME Desktop Environment.
      displayManager.gdm.enable = true;
      desktopManager.gnome.enable = true;
      # desktopManager.plasma6.enable = true;
    };
    snapper.configs = {
      home = {
        SUBVOLUME = "/home";
        ALLOW_USERS = [ "shogo" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = 5;
        TIMELINE_LIMIT_DAILY = 6;
        TIMELINE_LIMIT_WEEKLY = 3;
        TIMELINE_LIMIT_MONTHLY = 2;
        TIMELINE_LIMIT_YEARLY = 0;
      };
    };

  };
  # security.pam.services = {
  #   gdm.fprintAuth = false;
  #   login.fprintAuth = false;
  #   passwd.fprintAuth = false;
  # };

  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  networking.hostName = "micky"; # Define your hostname.

  virtualisation = {
    docker = {
      enable = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
      };
      storageDriver = "btrfs";
    };
  };

  # programs.seahorse.enable = false;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users = {
    shogotr = {
      isNormalUser = true;
      description = "Shogo Takata";
      extraGroups = [
        "networkmanager"
        "wheel"
        config.users.groups.keys.name
      ];
      # shell = pkgs.nushell;
    };
  };
  home-manager.users =
    let
      inherit (self.homeModules) nixos-common riken;
    in
    {
      shogotr = {
        imports = [
          nixos-common
          riken
        ];
      };
    };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 8080 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
}
