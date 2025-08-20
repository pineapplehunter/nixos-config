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
        system = "x86_64-linux";
        maxJobs = 32;
        supportedFeatures = [
          "big-parallel"
          "kvm"
          "benchmark"
          "nixos-test"
        ];
        sshUser = "takata";
        hostName = "kpro-njlab";
        speedFactor = 2;
      }
    ];
    settings = {
      connect-timeout = 10;
      builders-use-substitutes = true;
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
    desktopManager.gnome.extraGSettingsOverrides = ''
      [org.gnome.mutter]
      experimental-features=['scale-monitor-framebuffer', 'xwayland-native-scaling']

      [org.gnome.login-screen]
      enable-fingerprint-authentication=false
    '';

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

  # speedup boot
  systemd.services = {
    docker.wantedBy = lib.mkForce [ "default.target" ];
    ollama.wantedBy = lib.mkForce [ "default.target" ];
    libvirtd.wantedBy = lib.mkForce [ "default.target" ];
    libvirt-guests.wantedBy = lib.mkForce [ "default.target" ];
  };

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
        "tss" # for tpm
      ];
    };
  };
  home-manager.users =
    let
      inherit (self.homeModules)
        nixos-common
        shogo
        cradsec
        kpro
        ;
    in
    {
      takata = {
        imports = [
          nixos-common
          shogo
          kpro
          cradsec
        ];
      };
    };

  environment.systemPackages = with pkgs; [
    libselinux
    policycoreutils
    sbctl
    yubikey-manager
  ];
  # debug info for ease of debug
  environment.enableDebugInfo = true;

  security.tpm2.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  services.fprintd.enable = true;

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
  services.logind.lidSwitch = "suspend-then-hibernate";
  services.logind.lidSwitchDocked = "suspend-then-hibernate";
  services.logind.lidSwitchExternalPower = "suspend-then-hibernate";

  # services.automatic-timezoned.enable = true;
  services.fwupd.enable = true;
  systemd.package = pkgs.systemd.override { withSelinux = true; };

  environment.etc = {
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
  security.lsm = [
    "selinux"
    "ima"
  ];
}
