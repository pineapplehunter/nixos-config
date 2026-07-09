{
  flake.nixosModules.kernel-rust =
    { config, lib, ... }:
    let
      cfg = config.my.kernel-rust;
    in
    {
      options.my.kernel-rust.enable = lib.mkEnableOption "kernel rust";

      config = lib.mkIf cfg.enable {
        boot = {
          kernelPatches = [
            {
              name = "rust";
              patch = null;
              features = {
                rust = true;
              };
            }
          ];
        };
      };
    };
}
