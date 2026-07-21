{ config, inputs, ... }:
let
  home-mods = config.flake.homeModules;
  flake-config = config;
in
{
  flake.nixosModules.rpi5 =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports =
        let
          pi-mods = inputs.nixos-raspberrypi.nixosModules;
          os-mods = flake-config.flake.nixosModules;
        in
        [
          os-mods.common
          os-mods.ssh-authorized-keys
          os-mods.rpi5-garage
          # Hardware configuration
          pi-mods.raspberry-pi-5.base
          pi-mods.raspberry-pi-5.page-size-16k
          pi-mods.raspberry-pi-5.display-vc4
          ./pi5-configtxt.nix
          # Disk configuration
          # WARNING: formatting disk with disko is DESTRUCTIVE, check if
          # `disko.devices.disk.nvme0.device` is set correctly!
          ./disko.nix
        ];

      nixpkgs.overlays = [
        flake-config.flake.overlays.rpi5
      ];

      networking = {
        hostName = "rpi5";
        useNetworkd = true;
        wireless = {
          enable = false;
          iwd = {
            enable = true;
            settings = {
              Network = {
                EnableIPv6 = true;
                RoutePriorityOffset = 300;
              };
              Settings.AutoConnect = true;
            };
          };
        };
        firewall = {
          allowedUDPPorts = [ 5353 ];
          interfaces = {
            "tailscale0" = {
              allowedTCPPorts = [
                # prometheus smart
                9633
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
      };

      systemd = {
        network.networks = {
          "99-ethernet-default-dhcp".networkConfig.MulticastDNS = "yes";
          "99-wireless-client-dhcp".networkConfig.MulticastDNS = "yes";
        };
        # This comment was lifted from `srvos`
        # Do not take down the network for too long when upgrading,
        # This also prevents failures of services that are restarted instead of stopped.
        # It will use `systemctl restart` rather than stopping it with `systemctl stop`
        # followed by a delayed `systemctl start`.
        services = {
          systemd-networkd.stopIfChanged = false;
          # Services that are only restarted might be not able to resolve when resolved is stopped before
          systemd-resolved.stopIfChanged = false;
        };
      };

      services = {
        tailscale = {
          enable = true;
          useRoutingFeatures = "both";
        };
        prometheus.exporters = {
          smartctl.enable = true;
        };
        samba = {
          enable = true;
          openFirewall = true;
          settings = {
            "timemachine" = {
              "path" = "/samba/timemachine";
              "valid users" = "andy";
              "public" = "no";
              "writeable" = "yes";
              "force user" = "andy";
              # Below are the most imporant for macOS compatibility
              # Change the above to suit your needs
              "fruit:aapl" = "yes";
              "fruit:time machine" = "yes";
              "vfs objects" = "catia fruit streams_xattr";
            };
          };
        };
        # To be discoverable with windows
        samba-wsdd = {
          enable = true;
          openFirewall = true;
        };
        udev.extraRules = ''
          # Ignore partitions with "Required Partition" GPT partition attribute
          # On our RPis this is firmware (/boot/firmware) partition
          ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
            ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
            ENV{UDISKS_IGNORE}="1"
        '';
        avahi = {
          extraServiceFiles = {
            timemachine = ''
              <?xml version="1.0" standalone='no'?>
              <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
              <service-group>
                <name replace-wildcards="yes">%h</name>
                <service>
                  <type>_smb._tcp</type>
                  <port>445</port>
                </service>
                  <service>
                  <type>_device-info._tcp</type>
                  <port>0</port>
                  <txt-record>model=TimeCapsule8,119</txt-record>
                </service>
                <service>
                  <type>_adisk._tcp</type>
                  <!-- 
                    change tm_share to share name, if you changed it. 
                  --> 
                  <txt-record>dk0=adVN=tm_share,adVF=0x82</txt-record>
                  <txt-record>sys=waMa=0,adVF=0x100</txt-record>
                </service>
              </service-group>
            '';
          };
        };
        # Disable desktop services not needed on headless server
        xremap.enable = lib.mkForce false;
        printing.enable = lib.mkForce false;
        flatpak.enable = lib.mkForce false;
        pipewire.enable = lib.mkForce false;
      };

      virtualisation.docker = {
        enable = true;
        rootless.enable = true;
        daemon.settings = {
          fixed-cidr-v6 = "fd00::/80";
          ipv6 = true;
          log-driver = "local";
        };
      };

      programs.atop.enable = true;

      time.timeZone = "Asia/Tokyo";

      # Disable desktop services not needed on headless server
      i18n.inputMethod.enable = lib.mkForce false;
      pineapplehunter.japanese.enable = lib.mkForce false;
      nixos-artwork.enable = false;
      my.common-fonts.enable = false;
      my.common-packages.enable = false;

      environment.systemPackages = with pkgs; [
        nixd
        ghostty.terminfo
      ];

      system.nixos.tags = [
        "raspberry-pi"
        config.boot.kernelPackages.kernel.version
      ];

      boot.loader.raspberry-pi.bootloader = "kernel";

      # This is identical to what nixos installer does in
      # (modulesPash + "profiles/installation-device.nix")

      # Use less privileged nixos user
      users.users.shogo = {
        isNormalUser = true;
        extraGroups = [
          "garage"
          "networkmanager"
          "nix"
          "video"
          "wheel"
        ];
        openssh.authorizedKeys.keys = config.my.sshAuthorizedKeys;
      };

      users.users.andy = {
        isNormalUser = true;
        description = "Write-access to samba media shares";
        extraGroups = [ "users" ];
      };

      # Don't require sudo/root to `reboot` or `poweroff`.
      security.polkit.enable = true;

      # Automatically log in at the virtual consoles.
      services.getty.autologinUser = "shogo";

      # We run sshd by default. Login is only possible after adding a
      # password via "passwd" or by adding a ssh key to ~/.ssh/authorized_keys.
      # The latter one is particular useful if keys are manually added to
      # installation device for head-less systems i.e. arm boards by manually
      # mounting the storage in a different system.
      services.openssh.settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };

      boot.tmp.useTmpfs = true;

      # The following have been borrowed from:
      # https://github.com/nix-community/nixos-images/blob/b733f0680a42cc01d6ad53896fb5ca40a66d5e79/nix/image-installer/module.nix#L84
      console = {
        earlySetup = true;
        # ter-u22n is probably too big
        font = lib.mkDefault "${pkgs.terminus_font}/share/consolefonts/ter-u16n.psf.gz";

        # Make colored console output more readable
        # for example, `ip addr`s (blues are too dark by default)
        # Tango theme: https://yayachiken.net/en/posts/tango-colors-in-terminal/
        colors = lib.mkDefault [
          "000000"
          "CC0000"
          "4E9A06"
          "C4A000"
          "3465A4"
          "75507B"
          "06989A"
          "D3D7CF"
          "555753"
          "EF2929"
          "8AE234"
          "FCE94F"
          "739FCF"
          "AD7FA8"
          "34E2E2"
          "EEEEEC"
        ];
      };

      # allow nix-copy to live system
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

    };
}
