{
  flake.nixosModules.nixos-artwork =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      artwork-wallpapers = pkgs.symlinkJoin {
        name = "nixos-artwork-wallpapers";
        paths = lib.filter lib.isDerivation (lib.attrValues pkgs.nixos-artwork.wallpapers);
      };
    in
    {
      options.nixos-artwork.enable = lib.mkEnableOption "nixos artwork wallpapers";
      config.environment.systemPackages = lib.mkIf config.nixos-artwork.enable [ artwork-wallpapers ];
    };
}
