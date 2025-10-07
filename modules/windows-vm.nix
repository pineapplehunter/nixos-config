{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.pineapplehunter.windows-vm;
in
{
  options.pineapplehunter.windows-vm.enable = lib.mkEnableOption "windows VM";

  config = lib.mkIf cfg.enable {
    virtualisation = {
      libvirtd = {
        enable = true;
        qemu.swtpm.enable = true;
      };
    };
    programs.virt-manager.enable = true;

    environment.systemPackages = [
      pkgs.win-virtio
      pkgs.win-spice
    ];

    networking.firewall.trustedInterfaces = [ "virbr0" ];
  };
}
