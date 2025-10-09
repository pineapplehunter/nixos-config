{
  flake.nixosModules.personal =
    { pkgs, lib, ... }:
    let
      artwork-wallpapers = pkgs.symlinkJoin {
        name = "nixos-artwork-wallpapers";
        paths = lib.filter lib.isDerivation (lib.attrValues pkgs.nixos-artwork.wallpapers);
      };
      flatpak-chrome-alias = pkgs.writeShellScriptBin "flatpak-chrome-alias" "flatpak run com.google.Chrome $@";
    in
    {
      environment.systemPackages = [
        pkgs.blender
        pkgs.jujutsu
        pkgs.nautilus-thumbnailer-stl
        pkgs.orca-slicer
        pkgs.vivado

        artwork-wallpapers
        flatpak-chrome-alias
      ];
    };
}
