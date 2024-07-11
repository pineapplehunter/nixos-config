# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.consoleMode = "0";
  #boot.loader.efi.canTouchEfiVariables = true;
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "riscv64-linux"
  ];

  nix = {
    # package = pkgs.nixVersions.latest;
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
        speedFactor = 2;
      }
      {
        system = "x86_64-linux,aarch64-linux,riscv64-linux";
        maxJobs = 8;
        supportedFeatures = [
          "big-parallel"
          "kvm"
          "benchmark"
          "nixos-test"
        ];
        sshUser = "shogo";
        hostName = "action";
        speedFactor = 1;
      }
    ];
    extraOptions = ''
      builders-use-substitutes = true
    '';
  };

  networking.hostName = "beast"; # Define your hostname.
  networking.networkmanager.enable = true;

  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;

    # Enable the GNOME Desktop Environment.
    desktopManager.gnome.enable = true;
    displayManager.gdm = {
      enable = true;
      autoSuspend = false;
    };
  };
  # services.displayManager.autoLogin = {
  #   enable = true;
  #   user = "shogo";
  # };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.shogo = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
  };
  home-manager.users = {
    inherit (import ../../home) shogo;
  };

  system.stateVersion = config.system.nixos.release;
}
