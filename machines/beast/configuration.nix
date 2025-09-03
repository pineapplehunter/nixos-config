# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  pkgs,
  lib,
  self,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./immich-related.nix
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
  # turns out trying to prevent all writes may be a bad idea
  systemd = {
    tmpfiles.settings."bcache" = {
      "/sys/block/bcache0/bcache/cache_mode".w.argument = "writeback";
      "/sys/block/bcache0/bcache/writeback_percent".w.argument = "30";
      "/sys/block/bcache0/bcache/sequential_cutoff".w.argument = toString (64 * 1024 * 1024); # 64M
      "/sys/block/bcache0/bcache/writeback_delay".w.argument = toString 30; # 30 secs
      "/sys/block/bcache0/bcache/cache/congested_read_threshold_us".w.argument = "2000";
      "/sys/block/bcache0/bcache/cache/congested_write_threshold_us".w.argument = "20000";
    };

    services."beesd@-".wantedBy = lib.mkForce [ ];
  };

  services = {
    # Enable the GNOME Desktop Environment.
    desktopManager.gnome = {
      enable = true;
      extraGSettingsOverrides = ''
        [org.gnome.mutter]
        experimental-features=['scale-monitor-framebuffer', 'xwayland-native-scaling', 'variable-refresh-rate']
      '';
    };
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
        TIMELINE_LIMIT_HOURLY = 3;
        TIMELINE_LIMIT_DAILY = 2;
        TIMELINE_LIMIT_WEEKLY = 0;
        TIMELINE_LIMIT_MONTHLY = 3;
        TIMELINE_LIMIT_YEARLY = 0;
      };

      home = {
        SUBVOLUME = "/home";
        ALLOW_USERS = [ "shogo" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = 0;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_WEEKLY = 2;
        TIMELINE_LIMIT_MONTHLY = 6;
        TIMELINE_LIMIT_YEARLY = 2;
      };
    };
    prometheus.exporters.node.enable = true;

    localtimed.enable = true;

    beesd.filesystems."-" = {
      spec = "UUID=20f60216-a9ad-46c7-bbc5-fd6cc4a17a39";
      # use recommended value
      # multiplied by 8 for 8TB storage
      # https://github.com/Zygo/bees/blob/master/docs/config.md
      hashTableSizeMB = 128 * 8;
      extraOptions = [
        "--loadavg-target"
        "1"
      ];
    };
  };

  networking = {
    hostName = "beast"; # Define your hostname.
    networkmanager.enable = true;
    firewall.interfaces."tailscale0" = {
      allowedTCPPorts = [
        # prometheus node-exporter
        9100
        # ollama
        4000
        # immich
        2283
        # prometheus switchbot-exporter
        3725
      ];
      allowedTCPPortRanges = [
        # garage original
        {
          from = 3900;
          to = 3905;
        }
        #garage proxied
        {
          from = 3950;
          to = 3955;
        }
      ];
    };
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
