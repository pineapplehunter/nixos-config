{ inputs, ... }:
{
  flake.nixosModules.secureboot =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.my.secureboot;
    in
    {
      imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

      options.my.secureboot.enable = lib.mkEnableOption "secureboot support";

      config = lib.mkIf cfg.enable {
        boot = {
          loader.systemd-boot.enable = lib.mkForce false;
          lanzaboote = {
            enable = true;
            pkiBundle = "/var/lib/sbctl";
          };
        };

        environment.systemPackages = with pkgs; [
          sbctl
        ];
      };

    };
}
