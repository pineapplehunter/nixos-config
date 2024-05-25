# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  services.xremap = {
    withGnome = true;
    yamlConfig = ''
      modmap:
        - name: caps-esc
          remap:
            CapsLock: Esc
    '';
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
  boot.binfmt.emulatedSystems = [ "aarch64-linux" "riscv64-linux" ];
  boot.plymouth.enable = true;

  # https://discourse.nixos.org/t/suspend-then-hibernate/31953/5
  # boot.resumeDevice = "/dev/disk/by-uuid/244fb3a7-4e9c-4707-9427-a33f667a08bd";
  powerManagement.enable = true;
  powerManagement.powertop.enable = true;
  services.thermald.enable = true;

  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.services.docker.enable = false;
  systemd.sockets.docker.enable = false;

  networking.hostName = "micky"; # Define your hostname.
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/" ];
  };
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

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

  services.snapper.configs = {
    home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ "shogo" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = "5";
      TIMELINE_LIMIT_DAILY = "6";
      TIMELINE_LIMIT_WEEKLY = "3";
      TIMELINE_LIMIT_MONTHLY = "2";
      TIMELINE_LIMIT_YEARLY = "0";
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
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users = {
    shogotr = {
      isNormalUser = true;
      description = "Shogo Takata";
      extraGroups = [ "networkmanager" "wheel" ];
      # packages = with pkgs; [
      # firefox
      #  thunderbird
      # ];
      # shell = pkgs.nushell;
    };
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 8080 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  system.stateVersion = config.system.nixos.release;

}
