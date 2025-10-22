{ inputs, config, ... }:
let
  home-mods = config.flake.homeModules;
  os-mods = config.flake.nixosModules;

  configuration =
    {
      pkgs,
      lib,
      ...
    }:

    {
      imports = [
        # Include the results of the hardware scan.
        ./hardware-configuration.nix
        ./pam.nix
      ];

      boot.kernelPatches = [
        {
          name = "selinux";
          patch = null;
          structuredExtraConfig.SECURITY_SELINUX = lib.kernel.yes;
        }
        {
          name = "ipe";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            SECURITY_IPE = yes;
          };
        }
      ];
      my = {
        ima.enable = true;
      };

      # nixpkgs.flake.source = lib.mkForce null;
      nix = {
        distributedBuilds = true;
        buildMachines = [
          {
            hostName = "kpro-njlab";
            maxJobs = 32;
            speedFactor = 4;
            sshUser = "takata";
            supportedFeatures = [
              "big-parallel"
              "kvm"
              "benchmark"
              "nixos-test"
            ];
            systems = [
              "aarch64-linux"
              "riscv64-linux"
              "x86_64-linux"
            ];
          }
          {
            hostName = "daniel-njlab-pc";
            maxJobs = 16;
            speedFactor = 2;
            sshUser = "shogo";
            supportedFeatures = [
              "big-parallel"
              "kvm"
              "benchmark"
              "nixos-test"
            ];
            system = "x86_64-linux";
          }
        ];
        settings = {
          builders-use-substitutes = true;
          connect-timeout = 10;
        };
        # channel.enable = false;
      };

      # zramSwap.enable = true;

      services = {
        xremap = {
          enable = true;
          withGnome = true;
          watch = true;
          config.modmap = [
            {
              name = "caps-esc";
              remap = {
                "CapsLock" = "Esc";
              };
            }
          ];
        };

        thermald.enable = true;

        btrfs.autoScrub = {
          enable = true;
          fileSystems = [ "/" ];
        };

        # Enable the GNOME Desktop Environment.
        displayManager.gdm.enable = true;
        desktopManager.gnome.enable = true;

        snapper.configs = {
          home = {
            SUBVOLUME = "/home";
            ALLOW_USERS = [ "takata" ];
            TIMELINE_CREATE = true;
            TIMELINE_CLEANUP = true;
            TIMELINE_LIMIT_HOURLY = 10;
            TIMELINE_LIMIT_DAILY = 7;
            TIMELINE_LIMIT_WEEKLY = 4;
            TIMELINE_LIMIT_MONTHLY = 10;
            TIMELINE_LIMIT_YEARLY = 2;
          };
        };

        # ollama.enable = true;

        tailscale = {
          enable = true;
          useRoutingFeatures = "client";
        };

        # pcscd.enable = true;

        journald.audit = true;

        # disable for security purposes
        avahi.enable = false;

        tlp.enable = false;
        tuned.enable = true;
      };

      # Bootloader.

      boot = {
        loader.systemd-boot.enable = lib.mkForce false;
        lanzaboote = {
          enable = true;
          pkiBundle = "/var/lib/sbctl";
        };
        binfmt.emulatedSystems = [
          "aarch64-linux"
          "riscv64-linux"
          "riscv32-linux"
          "wasm32-wasi"
        ];
        supportedFilesystems = [ "btrfs" ];
      };

      networking = {
        hostName = "kpro-takata"; # Define your hostname.
        # Enable networking
        networkmanager.enable = true;

        firewall.interfaces = {
          "tailscale0" = {
            allowedTCPPortRanges = [
              {
                # kde connect
                from = 1714;
                to = 1764;
              }
            ];
            allowedUDPPortRanges = [
              {
                # kde connect
                from = 1714;
                to = 1764;
              }
            ];
          };
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
        podman.enable = true;
        windows.enable = true;
        libvirtd.enable = true;
      };

      programs = {
        virt-manager.enable = true;

        niri.enable = true;
      };

      # Define a user account. Don't forget to set a password with ‘passwd’.
      users.users = {
        takata = {
          isNormalUser = true;
          description = "Shogo Takata";
          extraGroups = [
            "networkmanager"
            "wheel"
            "dialout"
          ];
        };
      };
      home-manager.users = {
        takata = {
          imports = [
            home-mods.nixos-common
            home-mods.kpro
            home-mods.cradsec
          ];
        };
      };

      environment = {
        systemPackages = with pkgs; [
          checkpolicy
          clamav
          e2fsprogs
          libselinux
          policycoreutils
          sbctl
          selinux-python
          setools
          yubikey-manager
          (coreutils-full.override { selinuxSupport = true; })
        ];

        # debug info for ease of debug
        enableDebugInfo = true;

        etc = {
          "selinux/config".text = ''
            SELINUX=permissive
            SELINUXTYPE=refpolicy
          '';
          "selinux/semanage.conf".text = ''
            compiler-directory = ${pkgs.policycoreutils}/libexec/selinux/hll

            [load_policy]
            path = ${lib.getExe' pkgs.policycoreutils "load_policy"}
            [end]

            [setfiles]
            path = ${lib.getExe' pkgs.policycoreutils "setfiles"}
            args = -q -c $@ $<
            [end]

            [sefcontext_compile]
            path = ${lib.getExe' pkgs.libselinux "sefcontext_compile"}
            args = -r $@
            [end]
          '';
        };
      };

      security = {
        lsm = [
          "selinux"
        ];
        audit.enable = true;
        auditd.enable = true;
      };

      services = {
        openssh.settings.PasswordAuthentication = false;

        fprintd.enable = true;

        # services.automatic-timezoned.enable = true;
        fwupd.enable = true;

        beesd.filesystems."-" = {
          spec = "UUID=77b7cb82-87a1-45ec-8306-1a8edad64fd1";
          # use recommended value
          # https://github.com/Zygo/bees/blob/master/docs/config.md
          hashTableSizeMB = 128;
        };
      };

      systemd = {
        package = pkgs.systemd.override { withSelinux = true; };

        services = {
          docker.wantedBy = lib.mkForce [ "default.target" ];
          ollama.wantedBy = lib.mkForce [ "default.target" ];
          libvirtd.wantedBy = lib.mkForce [ "default.target" ];
          libvirt-guests.wantedBy = lib.mkForce [ "default.target" ];
          "beesd@-" = {
            wantedBy = lib.mkForce [ "power-ac.target" ];
            requires = [ "power-ac.target" ];
          };
        };

        power-targets.enable = true;
        hibernation.enable = true;
      };

      system.activationScripts.selinux = {
        deps = [ "etc" ];
        text = ''
          install -d -m0755 /var/lib/selinux
          cmd="${lib.getExe' pkgs.policycoreutils "semodule"} -s refpolicy -i ${pkgs.selinux-refpolicy}/share/selinux/refpolicy/*.pp"
          skipSELinuxActivation=0

          if [ -f /var/lib/selinux/activate-check ]; then
            if [ "$(cat /var/lib/selinux/activate-check)" == "$cmd" ]; then
              skipSELinuxActivation=1
            fi
          fi

          if [ $skipSELinuxActivation -eq 0 ]; then
            eval "$cmd"
            echo "$cmd" >/var/lib/selinux/activate-check
          fi
        '';
      };
    };
in

{
  flake.nixosConfigurations.kpro-takata = inputs.nixpkgs.lib.nixosSystem {
    system = null;
    modules = [
      inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x1-13th-gen
      inputs.lanzaboote.nixosModules.lanzaboote
      os-mods.common
      os-mods.kpro
      configuration
    ];
  };
}
