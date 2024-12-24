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

  networking.hostName = "beast"; # Define your hostname.
  networking.networkmanager.enable = true;

  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;

    # Enable the GNOME Desktop Environment.
    desktopManager.gnome.enable = true;
    displayManager.gdm = {
      enable = true;
      autoSuspend = false;
    };
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.shogo = {
    isNormalUser = true;
    extraGroups = [
      "wheel" # Enable ‘sudo’ for the user.
      config.users.groups.keys.name
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
