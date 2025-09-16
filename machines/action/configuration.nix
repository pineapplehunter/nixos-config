# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  pkgs,
  config,
  lib,
  self,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./pam.nix
  ];

  pineapplehunter.windows-vm.enable = true;

  # nixpkgs.flake.source = lib.mkForce null;
  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        systems = [
          "aarch64-linux"
          "riscv64-linux"
          "x86_64-linux"
        ];
        maxJobs = 32;
        supportedFeatures = [
          "big-parallel"
          "kvm"
          "benchmark"
          "nixos-test"
        ];
        sshUser = "takata";
        hostName = "kpro-njlab";
        speedFactor = 4;
      }
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
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "riscv64-linux"
        ];
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
    # channel.enable = false;
  };

  zramSwap.enable = true;

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
    desktopManager.gnome = {
      enable = true;
      extraGSettingsOverrides = ''
        [org.gnome.mutter]
        experimental-features=['scale-monitor-framebuffer', 'xwayland-native-scaling', 'variable-refresh-rate']
      '';
    };

    snapper.configs = {
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

    ollama.enable = true;

    howdy.enable = true;
    howdy.settings.video.dark_threshold = 90;
    linux-enable-ir-emitter.enable = true;
    tailscale = {
      enable = true;
      useRoutingFeatures = "client";
    };

    pcscd.enable = true;
  };

  # Bootloader.

  boot = {
    loader.grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
      configurationLimit = 20;
      default = "saved";
      extraEntries = lib.mkAfter ''
        menuentry 'Windows Boot Manager' --class windows --class os $menuentry_id_option 'osprober-efi-DA91-D0F6' {
          savedefault
          insmod part_gpt
          insmod fat
          search --no-floppy --fs-uuid --set=root DA91-D0F6
          chainloader /EFI/Microsoft/Boot/bootmgfw.efi
        }
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
    # disable until https://github.com/NixOS/nixpkgs/pull/411777
    # extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
    binfmt.emulatedSystems = [
      "aarch64-linux"
      "riscv64-linux"
      "riscv32-linux"
      "wasm32-wasi"
    ];
    supportedFilesystems = [ "btrfs" ];
  };

  # https://discourse.nixos.org/t/suspend-then-hibernate/31953/5
  powerManagement.enable = true;

  # speedup boot
  systemd.services = {
    docker.wantedBy = lib.mkForce [ "default.target" ];
    ollama.wantedBy = lib.mkForce [ "default.target" ];
    libvirtd.wantedBy = lib.mkForce [ "default.target" ];
    libvirt-guests.wantedBy = lib.mkForce [ "default.target" ];
    "beesd@-" = {
      wantedBy = lib.mkForce [ "power-ac.target" ];
      requires = [ "power-ac.target" ];
    };
  };

  networking = {
    hostName = "action"; # Define your hostname.
    # Enable networking
    networkmanager.enable = true;

    # Open ports in the firewall.
    # firewall.allowedTCPPorts = [ 8080 ];
    # firewall.allowedUDPPorts = [ ... ];
    # Or disable the firewall altogether.
    # firewall.enable = false;
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
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users = {
    shogo = {
      isNormalUser = true;
      description = "Shogo Takata";
      extraGroups = [
        "networkmanager"
        "wheel"
        "dialout"
      ];
    };

    riken = {
      isNormalUser = true;
      description = "deprecated only left to view data";
    };
  };
  home-manager.users =
    let
      inherit (self.homeModules) nixos-common shogo cradsec;
    in
    {
      shogo = {
        imports = [
          nixos-common
          shogo
          cradsec
        ];
      };
    };

  environment.systemPackages = with pkgs; [
    yubikey-manager
    zoom-us
  ];
  # debug info for ease of debug
  environment.enableDebugInfo = true;

  security.tpm2 = {
    enable = true;
    abrmd.enable = true;
  };
  services.openssh.settings.PasswordAuthentication = false;

  security.polkit.extraConfig = ''
    /*
      hibernation
      https://ubuntuhandbook.org/index.php/2021/08/enable-hibernate-ubuntu-21-10/
    */
    polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.login1.hibernate" ||
            action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
            action.id == "org.freedesktop.upower.hibernate" ||
            action.id == "org.freedesktop.login1.handle-hibernate-key" ||
            action.id == "org.freedesktop.login1.hibernate-ignore-inhibit")
        {
            return polkit.Result.YES;
        }
    });
  '';
  services.logind.settings.Login = {
    lidSwitch = "suspend-then-hibernate";
    lidSwitchDocked = "suspend-then-hibernate";
    lidSwitchExternalPower = "suspend-then-hibernate";
  };

  services.automatic-timezoned.enable = true;

  services.beesd.filesystems."-" = {
    spec = "UUID=c73fb028-c49b-4d3e-8628-39e326535d46";
    # use recommended value
    # multiplied by 2 for 2TB storage
    # https://github.com/Zygo/bees/blob/master/docs/config.md
    hashTableSizeMB = 128 * 2;
  };
}
