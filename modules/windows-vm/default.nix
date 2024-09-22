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
        qemu = {
          swtpm.enable = true;
          ovmf.enable = true;
          ovmf.packages = [ pkgs.OVMFFull.fd ];
        };
      };
    };
    programs.virt-manager.enable = true;

    environment.systemPackages = builtins.attrValues {
      inherit (pkgs)
        win-virtio
        win-spice
        ;
    };
  };
}
