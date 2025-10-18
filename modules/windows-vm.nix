{
  flake.nixosModules.windows-vm =
    {
      pkgs,
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

        environment.systemPackages = [
          pkgs.win-virtio
          pkgs.win-spice
        ];

        networking.firewall.trustedInterfaces = [ "virbr0" ];
      };
    };
}
