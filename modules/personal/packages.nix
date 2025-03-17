{
  pkgs,
  lib,
  ...
}:
let
  artwork-wallpapers = (
    pkgs.symlinkJoin {
      name = "nixos-artwork-wallpapers";
      paths = lib.filter lib.isDerivation (builtins.attrValues pkgs.nixos-artwork.wallpapers);
    }
  );
  flatpak-chrome-alias = (
    pkgs.writeShellScriptBin "flatpak-chrome-alias" "flatpak run com.google.Chrome $@"
  );
in
{
  environment.systemPackages = [
    # pkgs.orca-slicer
    pkgs.blender
    pkgs.jujutsu
    pkgs.nautilus-thumbnailer-stl
    pkgs.slack
    pkgs.vivado
    pkgs.webcord

    artwork-wallpapers
    flatpak-chrome-alias
  ];
}
