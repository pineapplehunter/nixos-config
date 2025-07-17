# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  self,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  pineapplehunter.windows-vm.enable = true;

  nix = {
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
        speedFactor = 1;
      }
    ];
    extraOptions = ''
      builders-use-substitutes = true
    '';
  };

  environment.systemPackages = [
    pkgs.podman-compose
    pkgs.geesefs
  ];

  # Use the systemd-boot EFI boot loader.
  boot = {
    loader.systemd-boot.enable = true;
    loader.systemd-boot.consoleMode = "0";
    #boot.loader.efi.canTouchEfiVariables = true;
    binfmt.emulatedSystems = [
      "aarch64-linux"
      "riscv64-linux"
      "riscv32-linux"
    ];
    plymouth.enable = false;
  };

  # for bcache writeback
  # https://wiki.archlinux.org/title/Bcache#Situation:_Prevent_all_write_access_to_a_HDD
  systemd.tmpfiles.settings."bcache" = {
    "/sys/block/bcache0/bcache/cache_mode".w.argument = "writeback";
    "/sys/block/bcache0/bcache/writeback_percent".w.argument = "0";
    "/sys/block/bcache0/bcache/sequential_cutoff".w.argument = "0";
    "/sys/block/bcache0/bcache/writeback_delay".w.argument = toString (7 * 24 * 60 * 60);
    "/sys/block/bcache1/bcache/cache_mode".w.argument = "writeback";
    "/sys/block/bcache1/bcache/writeback_percent".w.argument = "0";
    "/sys/block/bcache1/bcache/sequential_cutoff".w.argument = "0";
    "/sys/block/bcache1/bcache/writeback_delay".w.argument = toString (7 * 24 * 60 * 60);
    "/sys/fs/bcache/eca17911-1262-439c-bcb0-aff2495bce28/congested_read_threshold_us".w.argument = "0";
    "/sys/fs/bcache/eca17911-1262-439c-bcb0-aff2495bce28/congested_write_threshold_us".w.argument = "0";
  };

  networking.hostName = "beast"; # Define your hostname.
  networking.networkmanager.enable = true;

  services = {
    # Enable the GNOME Desktop Environment.
    desktopManager.gnome.enable = true;
    displayManager.gdm = {
      enable = true;
      autoSuspend = false;
    };
    tailscale = {
      enable = true;
      useRoutingFeatures = "both";
    };
    btrfs.autoScrub = {
      enable = true;
      fileSystems = [ "/" ];
    };
    snapper.configs = {
      garage = {
        SUBVOLUME = "/garage";
        ALLOW_USERS = [ "shogo" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = 10;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_WEEKLY = 4;
        TIMELINE_LIMIT_MONTHLY = 10;
        TIMELINE_LIMIT_YEARLY = 2;
      };

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
    prometheus.exporters.node.enable = true;

    localtimed.enable = true;
  };

  virtualisation = {
    docker = {
      enable = true;
      storageDriver = "btrfs";
    };
    podman.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.shogo = {
    isNormalUser = true;
    extraGroups = [
      "wheel" # Enable ‘sudo’ for the user.
    ];
  };

  home-manager.users =
    let
      inherit (self.homeModules) nixos-common shogo;
    in
    {
      shogo = {
        imports = [
          nixos-common
          shogo
        ];
      };
    };

}
