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
      config = lib.mkIf cfg.enable {
        boot.kernelParams = lib.flatten (
          lib.map (x: [
            "i915.force_probe=!${x}"
            "xe.force_probe=${x}"
          ]) cfg.devices
        );
      };
    };
}
