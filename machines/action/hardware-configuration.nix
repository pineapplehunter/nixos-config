# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  nixpkgs.system = "x86_64-linux";

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "nvme"
    "usb_storage"
    "sd_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];
  boot.resumeDevice = "/dev/disk/by-uuid/244fb3a7-4e9c-4707-9427-a33f667a08bd";

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/c73fb028-c49b-4d3e-8628-39e326535d46";
    fsType = "btrfs";
    options = [ "subvol=@,autodefrag,commit=120,compress=zstd,noatime,space_cache=v2" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/c73fb028-c49b-4d3e-8628-39e326535d46";
    fsType = "btrfs";
    options = [ "subvol=@home,autodefrag,commit=120,compress=zstd,noatime,space_cache=v2" ];
  };

  fileSystems."/efi" = {
    device = "/dev/disk/by-uuid/DA91-D0F6";
    fsType = "vfat";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/8057-31F0";
    fsType = "vfat";
  };

  #fileSystems."/efi/EFI/Linux" = { device = "/boot/EFI/Linux"; options = [ "bind" ]; };
  #fileSystems."/efi/EFI/nixos" = { device = "/boot/EFI/nixos"; options = [ "bind" ]; };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp0s13f0u1u1.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp0s20f3.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  #powerManagement.powertop.enable = true;
  hardware.sensor.iio.enable = true;
}
