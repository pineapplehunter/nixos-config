{
  flake.nixosModules.fsverity =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.my.fsverity;
    in
    {

      options.my.fsverity = {
        enable = lib.mkEnableOption "fsverity support";
      };

      config = lib.mkIf cfg.enable {
        boot = {
          kernelPatches = [
            {
              name = "ima";
              patch = null;
              structuredExtraConfig = with lib.kernel; {
                FS_VERITY = yes;
              };
            }
          ];
        };

        environment.systemPackages = [ pkgs.fsverity-utils ];

      };
    };
}
