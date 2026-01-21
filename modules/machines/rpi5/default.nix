{ config, inputs, ... }:
let
  home-mods = config.flake.homeModules;
  flake-config = config;
in
{
  flake.nixosModules.rpi5 = {
    imports =
      let
        pi-mods = inputs.nixos-raspberrypi.nixosModules;
        os-mods = config.flake.nixosModules;
      in
      [
        # os-mods.common
        # os-mods.personal
        os-mods.rpi5-garage
        # Hardware configuration
        pi-mods.raspberry-pi-5.base
        pi-mods.raspberry-pi-5.page-size-16k
        pi-mods.raspberry-pi-5.display-vc4
        inputs.disko.nixosModules.disko
        inputs.home-manager.nixosModules.default
        inputs.agenix.nixosModules.default
        ./pi5-configtxt.nix
        ./modules/nice-looking-console.nix
        (
          { config, pkgs, ... }:
          {

            age = {
              secrets.access_tokens = {
                file = flake-config.ageFile.access-tokens;
                mode = "0440";
                group = "wheel";
              };
            };
            networking.useNetworkd = true;
            networking.nftables.enable = true;
            systemd.network.networks = {
              "99-ethernet-default-dhcp".networkConfig.MulticastDNS = "yes";
              "99-wireless-client-dhcp".networkConfig.MulticastDNS = "yes";
            };

            boot.loader.raspberryPi.bootloader = "kernel";

            # This comment was lifted from `srvos`
            # Do not take down the network for too long when upgrading,
            # This also prevents failures of services that are restarted instead of stopped.
            # It will use `systemctl restart` rather than stopping it with `systemctl stop`
            # followed by a delayed `systemctl start`.
            systemd.services = {
              systemd-networkd.stopIfChanged = false;
              # Services that are only restarted might be not able to resolve when resolved is stopped before
              systemd-resolved.stopIfChanged = false;
            };

            # Use iwd instead of wpa_supplicant. It has a user friendly CLI
            networking.wireless.enable = false;
            networking.wireless.iwd = {
              enable = true;
              settings = {
                Network = {
                  EnableIPv6 = true;
                  RoutePriorityOffset = 300;
                };
                Settings.AutoConnect = true;
              };
            };
            # mdns
            networking.firewall = {
              allowedUDPPorts = [ 5353 ];
              interfaces = {
                "tailscale0" = {
                  allowedTCPPorts = [
                    # prometheus node-exporter
                    9100
                  ];
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

            services.tailscale = {
              enable = true;
              useRoutingFeatures = "both";
            };

            services.beesd.filesystems = {
              "root" = {
                spec = "/";
                hashTableSizeMB = 128;
              };
              "garage" = {
                spec = "/garage";
                hashTableSizeMB = 128;
              };
            };

            services.prometheus.exporters.node.enable = true;

            programs.atop.enable = true;
            programs.zsh.enable = true;

            time.timeZone = "Asia/Tokyo";
            networking.hostName = "rpi5";

            services.udev.extraRules = ''
              # Ignore partitions with "Required Partition" GPT partition attribute
              # On our RPis this is firmware (/boot/firmware) partition
              ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
                ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
                ENV{UDISKS_IGNORE}="1"
            '';

            services.avahi = {
              enable = true;
              nssmdns4 = true;
              openFirewall = true;
            };

            environment.systemPackages = with pkgs; [
              tree
              helix
              nixd
              nixfmt
              git
            ];

            users.users.shogo.openssh.authorizedKeys.keys = [
              # YOUR SSH PUB KEY HERE #

            ];
            users.users.root.openssh.authorizedKeys.keys = [
              # YOUR SSH PUB KEY HERE #

            ];

            system.nixos.tags =
              let
                cfg = config.boot.loader.raspberryPi;
              in
              [
                "raspberry-pi-${cfg.variant}"
                cfg.bootloader
                config.boot.kernelPackages.kernel.version
              ];

            # This is identical to what nixos installer does in
            # (modulesPash + "profiles/installation-device.nix")

            # Use less privileged nixos user
            users.users.shogo = {
              isNormalUser = true;
              extraGroups = [
                "wheel"
                "networkmanager"
                "video"
              ];
              # Allow the graphical user to login without password
              initialHashedPassword = "";
            };

            # Allow the user to log in as root without a password.
            users.users.root.initialHashedPassword = "";

            users.defaultUserShell = pkgs.zsh;

            # Don't require sudo/root to `reboot` or `poweroff`.
            security.polkit.enable = true;

            # Allow passwordless sudo from nixos user
            security.sudo-rs = {
              enable = true;
            };

            # Automatically log in at the virtual consoles.
            services.getty.autologinUser = "shogo";

            # We run sshd by default. Login is only possible after adding a
            # password via "passwd" or by adding a ssh key to ~/.ssh/authorized_keys.
            # The latter one is particular useful if keys are manually added to
            # installation device for head-less systems i.e. arm boards by manually
            # mounting the storage in a different system.
            services.openssh = {
              enable = true;
              startWhenNeeded = true;
              settings.PermitRootLogin = "yes";
            };

            # allow nix-copy to live system
            nix = {
              settings = {
                trusted-users = [ "@wheel" ];
                experimental-features = [
                  "auto-allocate-uids"
                  "cgroups"
                  "flakes"
                  "nix-command"
                  "no-url-literals"
                ];
              };
              extraOptions = ''
                !include ${config.age.secrets.access_tokens.path}
              '';
            };

            # We are stateless, so just default to latest.
            system.stateVersion = config.system.nixos.release;
          }
        )
        # Disk configuration
        # WARNING: formatting disk with disko is DESTRUCTIVE, check if
        # `disko.devices.disk.nvme0.device` is set correctly!
        ./disko.nix
        # { networking.hostId = "8821e309"; } # NOTE: for zfs, must be unique
        # Further user configuration
        {
          boot.tmp.useTmpfs = true;
        }

        # Advanced: Use non-default kernel from kernel-firmware bundle
        # (
        #   {
        #     config,
        #     pkgs,
        #     lib,
        #     ...
        #   }:
        #   let
        #     kernelBundle = pkgs.linuxAndFirmware.v6_6_31;
        #   in
        #   {
        #     boot = {
        #       loader.raspberryPi.firmwarePackage = kernelBundle.raspberrypifw;
        #       loader.raspberryPi.bootloader = "kernel";
        #       kernelPackages = kernelBundle.linuxPackages_rpi5;
        #     };

        #     nixpkgs.overlays = [
        #       (final: prev: {
        #         # This is used in (modulesPath + "/hardware/all-firmware.nix") when at least
        #         # enableRedistributableFirmware is enabled
        #         # I know no easier way to override this package
        #         inherit (kernelBundle) raspberrypiWirelessFirmware;
        #         # Some derivations want to use it as an input,
        #         # e.g. raspberrypi-dtbs, omxplayer, sd-image-* modules
        #         inherit (kernelBundle) raspberrypifw;
        #       })
        #       inputs.agenix.overlays.default
        #     ];
        #   }
        # )
        (
          { pkgs, ... }:
          {
            nixpkgs.overlays = [
              inputs.agenix.overlays.default
            ];
          }
        )
      ];

    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "hm-backup";
      users = {
        shogo = {
          imports = [
            home-mods.minimal
            home-mods.shogo
          ];
        };
      };
    };

    environment = {
      variables = {
        BAT_THEME = "GitHub";
        EDITOR = "hx";
      };
      enableAllTerminfo = true;
    };
  };
}
