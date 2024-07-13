# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config
, pkgs
, lib
, ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # nixpkgs.flake.source = lib.mkForce null;
  nix = {
    package = pkgs.nixVersions.latest;
    distributedBuilds = true;
    buildMachines = [
      {
        system = "x86_64-linux";
        maxJobs = 16;
        supportedFeatures = [
          "big-parallel"
          "kvm"
          "benchmark"
          "nixos-test"
        ];
        sshUser = "shogo";
        hostName = "daniel-njlab-pc";
        # sshKey = "/home/shogo/.ssh/id_ecdsa.1";
        speedFactor = 2;
      }
      {
        system = "x86_64-linux,aarch64-linux,riscv64-linux";
        maxJobs = 16;
        supportedFeatures = [
          "big-parallel"
          "kvm"
          "benchmark"
          "nixos-test"
        ];
        sshUser = "shogo";
        hostName = "beast";
        # sshKey = "/home/shogo/.ssh/id_ecdsa.1";
        speedFactor = 2;
      }
    ];
    settings = {
      connect-timeout = 10;
      builders-use-substitutes = true;
    };
    extraOptions = ''
      !include ${config.sops.secrets.access_tokens.path}
    '';
    # channel.enable = false;
  };

  sops.secrets.access_tokens = {
    mode = "0440";
    group = config.users.groups.keys.name;
  };

  zramSwap.enable = true;

  services.xremap = {
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

  # Bootloader.

  boot.loader.grub = {
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
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "riscv64-linux"
  ];
  boot.supportedFilesystems = [
    "btrfs"
    "bcachefs"
  ];

  # https://discourse.nixos.org/t/suspend-then-hibernate/31953/5
  powerManagement.enable = true;
  powerManagement.powertop.enable = true;
  services.thermald.enable = true;

  systemd.services.docker.enable = false;
  systemd.sockets.docker.enable = false;

  networking.hostName = "action"; # Define your hostname.
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/" ];
  };

  # Enable networking
  networking.networkmanager.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
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
      auth       optional                    ${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so

      account    include                     login

      password   required                    pam_deny.so

      session    include                     login
      session    optional                    ${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so auto_start
    '';
  };

  services.snapper.configs = {
    home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ "shogo" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 10;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 10;
      TIMELINE_LIMIT_YEARLY = 2;
    };
  };

  virtualisation = {
    docker = {
      enable = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
      };
      storageDriver = "btrfs";
    };
    #podman.enable = true;
    libvirtd = {
      enable = true;
      qemu = {
        swtpm.enable = true;
        ovmf.enable = true;
        ovmf.packages = [ pkgs.OVMFFull.fd ];
      };
    };
  };
  programs.virt-manager.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users = {
    shogo = {
      isNormalUser = true;
      description = "Shogo Takata";
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
    };

    riken = {
      isNormalUser = true;
      description = "Shogo at Riken";
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
    };
  };
  home-manager.users = {
    inherit (import ../../home) shogo riken;
  };

  environment.systemPackages = with pkgs; [
    win-virtio
    win-spice
  ];

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 8080 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  system.stateVersion = config.system.nixos.release;

}
