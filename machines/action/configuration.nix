# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  pkgs,
  lib,
  self,
  config,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  pineapplehunter.windows-vm.enable = true;

  # nixpkgs.flake.source = lib.mkForce null;
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
    desktopManager.gnome.enable = true;

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
        "tss" # for tpm
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

  environment.systemPackages = [
    (pkgs.writeScriptBin "ai" ''
      ollama run deepseek-r1:8b
    '')
    pkgs.yubikey-manager
  ];
  # debug info for ease of debug
  environment.enableDebugInfo = true;

  security.tpm2.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  security.pam.services =
    let
      inherit (pkgs)
        fprintd
        gnome-keyring
        howdy
        linux-pam
        systemd
        ;
      # this directory will be wiped on every boot
      stamp-dir = "/var/run/pam-timeout";
      check-timeout = pkgs.writeShellScript "check-timeout.sh" ''
        PATH=${lib.makeBinPath [ pkgs.coreutils ]}
        # FIXME: this uses a plain text file that stores the time of
        # last login.  Check if this is fine with my threat model.
        # Hint for me: I assume no one except me has access to root user.
        if [ -z "$PAM_USER" ]; then
          echo no user is set
          exit 1
        fi
        STAMP_FILE="${stamp-dir}/$PAM_USER/password_login_time"
        MAX_AGE=$((12 * 60 * 60))  # 12 hours

        if [[ ! -f "$STAMP_FILE" ]]; then
          echo no stamp file found
          exit 1  # Require password
        fi

        last_time=$(< "$STAMP_FILE")
        now=$(date +%s)

        if (( now - last_time < MAX_AGE )); then
          exit 0  # OK to use fingerprint
        else
          exit 1  # Too old, force password
        fi
      '';

      update-timeout = pkgs.writeShellScript "update-timeout.sh" ''
        PATH=${lib.makeBinPath [ pkgs.coreutils ]}
        umask 077
        if [ -z "$PAM_USER" ]; then
          echo no user is set
          exit 1
        fi
        STAMP_DIR="${stamp-dir}/$PAM_USER"
        mkdir -p "$STAMP_DIR"
        date +%s > "$STAMP_DIR/password_login_time"
      '';

      # copied from nixpkgs
      # https://github.com/NixOS/nixpkgs/blob/caf5a7d2d10c4cc33d02cf16f540ba79d6ccd004/nixos/modules/security/pam.nix#L1502-L1514
      makeLimitsConf =
        limits:
        pkgs.writeText "limits.conf" (
          lib.concatMapStrings (
            {
              domain,
              type,
              item,
              value,
            }:
            "${domain} ${type} ${item} ${toString value}\n"
          ) limits
        );

      default-rule = ''
        # Account management.
        account required ${linux-pam}/lib/security/pam_unix.so

        # Authentication management.
        # This check introduces timeout on unix login.  It will only
        # allow fingerprint or other means of login it unix has not
        # timed out.  The control flow is created by skipping lines.
        # It calls check-timeout twice to prevent toctou attacks
        # !!! PLEASE CHECK SKIP LINES WHEN MODIFYING !!!
        auth [success=ignore default=3]      ${linux-pam}/lib/security/pam_exec.so quiet seteuid ${check-timeout}
        auth [success=1 default=ignore]      ${howdy}/lib/security/pam_howdy.so
        auth [success=ignore default=ignore] ${fprintd}/lib/security/pam_fprintd.so
        auth [success=4 default=ignore]      ${linux-pam}/lib/security/pam_exec.so quiet seteuid ${check-timeout}
        auth [success=1 default=ignore]      ${linux-pam}/lib/security/pam_unix.so likeauth nullok try_first_pass
        auth requisite                       ${linux-pam}/lib/security/pam_deny.so
        auth optional                        ${linux-pam}/lib/security/pam_exec.so quiet seteuid ${update-timeout}
        auth optional                        ${gnome-keyring}/lib/security/pam_gnome_keyring.so
        auth requisite                       ${linux-pam}/lib/security/pam_permit.so

        # Password management.
        password sufficient ${linux-pam}/lib/security/pam_unix.so nullok yescrypt
        password optional   ${gnome-keyring}/lib/security/pam_gnome_keyring.so use_authtok

        # Session management.
        session required ${linux-pam}/lib/security/pam_env.so conffile=/etc/pam/environment readenv=0
        session required ${linux-pam}/lib/security/pam_unix.so
        session required ${linux-pam}/lib/security/pam_loginuid.so
        session required ${linux-pam}/lib/security/pam_lastlog.so silent
        session optional ${systemd}/lib/security/pam_systemd.so
        session required ${linux-pam}/lib/security/pam_limits.so conf=${makeLimitsConf config.security.pam.services.login.limits}
        session optional ${gnome-keyring}/lib/security/pam_gnome_keyring.so auto_start
      '';
      only-unix-rule = ''
        # Authentication management.
        # This check introduces timeout on unix login.  It will only
        # allow fingerprint or other means of login it unix has not
        # timed out.  The control flow is created by skipping lines.
        # It calls check-timeout twice to prevent toctou attacks
        # !!! PLEASE CHECK SKIP LINES WHEN MODIFYING !!!
        auth [success=1 default=ignore] ${linux-pam}/lib/security/pam_unix.so likeauth nullok try_first_pass
        auth requisite                  ${linux-pam}/lib/security/pam_deny.so
        auth optional                   ${linux-pam}/lib/security/pam_exec.so quiet seteuid ${update-timeout}
        auth optional                   ${gnome-keyring}/lib/security/pam_gnome_keyring.so
        auth requisite                  ${linux-pam}/lib/security/pam_permit.so

        account  include default-auth
        password include default-auth
        sesstion include default-auth
      '';
      use-default-rule = ''
        auth      substack      default-auth
        account   include       default-auth
        password  substack      default-auth
        session   include       default-auth
      '';
      use-only-unix-rule = ''
        auth      substack      only-unix-auth
        account   include       only-unix-auth
        password  substack      only-unix-auth
        session   include       only-unix-auth
      '';
      deny-all-rule = ''
        auth      requisite ${linux-pam}/lib/security/pam_deny.so
        account   requisite ${linux-pam}/lib/security/pam_deny.so
        password  requisite ${linux-pam}/lib/security/pam_deny.so
        session   requisite ${linux-pam}/lib/security/pam_deny.so
      '';
    in
    {
      default-auth.text = default-rule;
      only-unix-auth.text = only-unix-rule;

      chfn.text = lib.mkForce use-only-unix-rule;
      chpasswd.text = lib.mkForce use-only-unix-rule;
      chsh.text = lib.mkForce use-only-unix-rule;
      cups.text = lib.mkForce use-default-rule;
      gdm-fingerprint.text = lib.mkForce deny-all-rule;
      gdm-password.text = lib.mkForce use-default-rule;
      groupadd.text = lib.mkForce use-default-rule;
      groupdel.text = lib.mkForce use-only-unix-rule;
      groupmems.text = lib.mkForce use-default-rule;
      groupmod.text = lib.mkForce use-only-unix-rule;
      login.text = lib.mkForce use-default-rule;
      passwd.text = lib.mkForce use-only-unix-rule;
      polkit-1.text = lib.mkForce use-default-rule;
      su.text = lib.mkForce use-default-rule;
      sudo-i.text = lib.mkForce use-default-rule;
      sudo.text = lib.mkForce use-default-rule;
      systemd-run0.text = lib.mkForce use-default-rule;
      useradd.text = lib.mkForce use-default-rule;
      userdel.text = lib.mkForce use-only-unix-rule;
      usermod.text = lib.mkForce use-only-unix-rule;
    };

  programs.dconf = {
    enable = true;
    profiles.gdm = {
      enableUserDb = true;
      databases = [
        {
          # disable finger print in /etc/pam.d/gdm-fingerprint
          settings."org/gnome/login-screen".enable-fingerprint-authentication = false;
        }
      ];
    };
  };
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

  services.automatic-timezoned.enable = true;
}
