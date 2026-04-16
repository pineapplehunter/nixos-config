{

  flake.nixosModules.xe-driver =
    { lib, config, ... }:
    let
      cfg = config.my.xe;
    in
    {
      options.my.xe = {
        enable = lib.mkEnableOption "enable xe driver";
        devices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "device ids to enable xe driver";
          example = [ "7d51" ];
        };
      };
      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            boot.initrd.availableKernelModules = [ "xe" ];
            boot.initrd.kernelModules = [ "xe" ];
            boot.kernelParams = lib.concatMap (x: [
              "i915.force_probe=!${x}"
              "xe.force_probe=${x}"
            ]) cfg.devices;
          }
          (lib.mkIf config.boot.plymouth.enable {
            boot.initrd.systemd.services.plymouth-start = {
              after = [ "systemd-modules-load.service" ];
              wants = [ "systemd-modules-load.service" ];
            };
          })
        ]
      );
    };
}
