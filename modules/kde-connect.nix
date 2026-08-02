{
  flake.nixosModules.kde-connect =
    { config, lib, ... }:
    let
      cfg = config.my.kde-connect.firewall;
    in
    {
      options.my.kde-connect.firewall.enable = lib.mkEnableOption "KDE Connect firewall rules";

      config = lib.mkIf cfg.enable {
        networking.firewall.interfaces."tailscale0" = {
          allowedTCPPortRanges = [
            {
              from = 1714;
              to = 1764;
            }
          ];
          allowedUDPPortRanges = [
            {
              from = 1714;
              to = 1764;
            }
          ];
        };
      };
    };
}
