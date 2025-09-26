# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  pkgs,
  lib,
  config,
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

  boot.kernelPatches = [
    {
      name = "selinux";
      patch = null;
      structuredExtraConfig.SECURITY_SELINUX = lib.kernel.yes;
    }
    {
      name = "ima";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        EVM = yes;
        IMA = yes;
        IMA_DEFAULT_HASH_SHA256 = yes;
        IMA_READ_POLICY = yes;
        IMA_WRITE_POLICY = yes;
      };
    }
  ];

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

  # https://discourse.nixos.org/t/suspend-then-hibernate/31953/5
  powerManagement.enable = true;

  networking = {
    hostName = "kpro-takata"; # Define your hostname.
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
  home-manager.users =
    let
      inherit (self.homeModules)
        nixos-common
        cradsec
        kpro
        ;
    in
    {
      takata = {
        imports = [
          nixos-common
          kpro
          cradsec
        ];
      };
    };

  environment = {
    systemPackages = with pkgs; [
      checkpolicy
      clamav
      e2fsprogs
      ima-evm-utils
      libselinux
      policycoreutils
      sbctl
      selinux-python
      setools
      yubikey-manager
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
    tpm2 = {
      enable = true;
      abrmd.enable = true;
    };
    polkit.extraConfig = ''
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
    lsm = [
      "selinux"
      "ima"
    ];
  };

  services = {
    openssh.settings.PasswordAuthentication = false;

    fprintd.enable = true;

    logind.settings.Login = {
      lidSwitch = "suspend-then-hibernate";
      lidSwitchDocked = "suspend-then-hibernate";
      lidSwitchExternalPower = "suspend-then-hibernate";
    };

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
    additionalUpstreamSystemUnits = lib.optionals config.systemd.tpm2.enable [
      "systemd-pcrfs-root.service"
      "systemd-pcrfs@.service"
      "systemd-pcrmachine.service"
      "systemd-pcrphase-initrd.service"
      "systemd-pcrphase-sysinit.service"
      "systemd-pcrphase.service"
    ];

    sleep.extraConfig = ''
      HibernateDelaySec=2h
    '';

    services = {
      docker.wantedBy = lib.mkForce [ "default.target" ];
      ollama.wantedBy = lib.mkForce [ "default.target" ];
      libvirtd.wantedBy = lib.mkForce [ "default.target" ];
      libvirt-guests.wantedBy = lib.mkForce [ "default.target" ];
      "beesd@-" = {
        wantedBy = lib.mkForce [ "power-ac.target" ];
        requires = [ "power-ac.target" ];
      };
      adjust-backlight-resume = {
        description = "adjust backlight after suspend";
        wantedBy = [ "suspend.target" ];
        after = [ "suspend.target" ];
        path = [ pkgs.coreutils ];
        script = ''
          sleep 2
          BACKLIGHT=/sys/class/backlight/intel_backlight/brightness
          if [ -f $BACKLIGHT ]; then
            echo setting backlight
            cat $BACKLIGHT | tee $BACKLIGHT
          fi
        '';
      };
      adjust-backlight-boot = {
        description = "adjust backlight after boot";
        wantedBy = [ "default.target" ];
        path = [ pkgs.coreutils ];
        script = ''
          sleep 2
          BACKLIGHT=/sys/class/backlight/intel_backlight/brightness
          if [ -f $BACKLIGHT ]; then
            echo setting backlight
            cat $BACKLIGHT | tee $BACKLIGHT
          fi
        '';
      };
    };
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
}
