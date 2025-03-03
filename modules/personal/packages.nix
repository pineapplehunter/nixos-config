{
  pkgs,
  self,
  lib,
  ...
}:
{
  environment.systemPackages = builtins.attrValues {
    inherit (pkgs)
      blender
      webcord
      slack
      jujutsu
      vivado
      # orca-slicer
      ;
    artwork-wallpapers = pkgs.symlinkJoin {
      name = "nixos-artwork-wallpapers";
      paths = lib.filter lib.isDerivation (builtins.attrValues pkgs.nixos-artwork.wallpapers);
    };
    # inherit (pkgs.jetbrains) idea-ultimate;
    flatpak-chrome-alias = pkgs.writeShellScriptBin "flatpak-chrome-alias" "flatpak run com.google.Chrome $@";
    inherit (self.packages.${pkgs.system}) nautilus-thumbnailer-stl;
  };
}
