{
  flake.nixosModules.kpro =
    { pkgs, lib, ... }:
    let
      artwork-wallpapers = pkgs.symlinkJoin {
        name = "nixos-artwork-wallpapers";
        paths = lib.filter lib.isDerivation (lib.attrValues pkgs.nixos-artwork.wallpapers);
      };
    in
    {
      environment.systemPackages = [ artwork-wallpapers ];
    };
}
