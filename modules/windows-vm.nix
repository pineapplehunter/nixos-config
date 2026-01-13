{
  flake.nixosModules.windows-vm =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.virtualisation.windows;
    in
    {
      options.virtualisation.windows.enable = lib.mkEnableOption "windows VM";

      config = lib.mkIf cfg.enable {
        virtualisation.libvirtd.qemu.swtpm.enable = true;

        networking.firewall.trustedInterfaces = [ "virbr0" ];
      };
    };
}
