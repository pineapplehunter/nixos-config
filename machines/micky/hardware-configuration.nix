# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  nixpkgs.system = "x86_64-linux";

  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "vmd" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/09dc48d7-a436-4ec9-be37-173da225dcb1";
      fsType = "btrfs";
      options =
        [ "subvol=@,autodefrag,commit=120,compress=zstd,noatime,space_cache=v2" ];
    };

  fileSystems."/home" =
    {
      device = "/dev/disk/by-uuid/09dc48d7-a436-4ec9-be37-173da225dcb1";
      fsType = "btrfs";
      options =
        [ "subvol=@home,autodefrag,commit=120,compress=zstd,noatime,space_cache=v2" ];
    };

  fileSystems."/swap" =
    {
      device = "/dev/disk/by-uuid/09dc48d7-a436-4ec9-be37-173da225dcb1";
      fsType = "btrfs";
      options =
        [ "subvol=@swap,autodefrag,commit=120,compress=zstd,noatime,space_cache=v2" ];
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/D550-EA8E";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  swapDevices = [{ device = "/swap/swapfile"; }];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlo1.useDHCP = lib.mkDefault true;
  # networking.interfaces.wwp0s20f0u3.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
