# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, ... }:
let
  home-mods = config.flake.homeModules;
  os-mods = config.flake.nixosModules;
in
{
  flake.nixosModules.beast =
    {
      pkgs,
      ...
    }:
    {
      imports = [
        # Include the results of the hardware scan.
        os-mods.common
        os-mods.personal
        os-mods.beast-hardware
        os-mods.beast-immich-related
      ];

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
        pkgs.geesefs
        pkgs.podman-compose
        pkgs.smartmontools
        pkgs.vivado
      ];

      # Use the systemd-boot EFI boot loader.
      boot = {
        loader.systemd-boot = {
          enable = true;
          consoleMode = "0";
          configurationLimit = 30;
        };
        #boot.loader.efi.canTouchEfiVariables = true;
        binfmt.emulatedSystems = [
          "aarch64-linux"
          "riscv64-linux"
          "riscv32-linux"
        ];
        plymouth.enable = false;
      };

      systemd.services = {
        bcache-setup = {
          description = "Initial setup for bcache";
          path = [ pkgs.bcache-tools ];
          script = ''
            bcache set-cachemode /dev/disk/by-uuid/fed831d5-efca-4101-a6e8-5abde217964c writearound
            bcache set-cachemode /dev/disk/by-uuid/97d0acab-c4d0-4987-8f46-055cfc9a06c1 writearound
          '';
          serviceConfig.Type = "oneshot";
          wantedBy = [ "default.target" ];
        };
        # disable display manager on boot
        display-manager.enable = false;
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

          immich = {
            SUBVOLUME = "/immich";
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

        fwupd.enable = true;

        beesd.filesystems = {
          "-" = {
            spec = "UUID=20f60216-a9ad-46c7-bbc5-fd6cc4a17a39";
            hashTableSizeMB = 1024;
          };
        };

        smartd.enable = true;
      };

      networking = {
        hostName = "beast"; # Define your hostname.
        networkmanager.enable = true;
        firewall.interfaces = {
          "tailscale0" = {
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
          "wlp36s0" = {
            allowedTCPPortRanges = [
              # garage original
              {
                from = 3900;
                to = 3905;
              }
            ];
          };
        };
      };

      virtualisation = {
        docker = {
          enable = true;
          storageDriver = "btrfs";
        };
        podman.enable = true;
        libvirtd.enable = true;
        windows.enable = true;
      };

      programs = {
        virt-manager.enable = true;
      };

      # Define a user account. Don't forget to set a password with ‘passwd’.
      users.users.shogo = {
        isNormalUser = true;
        extraGroups = [
          "wheel" # Enable ‘sudo’ for the user.
        ];
      };

      home-manager.users = {
        shogo = {
          imports = [
            home-mods.nixos-common
            home-mods.shogo
          ];
        };
      };

      zramSwap.enable = true;
    };
}
