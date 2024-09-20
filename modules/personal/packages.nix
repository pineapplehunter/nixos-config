{ pkgs, self, ... }:
{
  environment.systemPackages = builtins.attrValues {
    inherit (pkgs)
      blender
      webcord
      slack
      curl-http3
      jujutsu
      vivado
      nixos-artwork-wallpaper
      jdk
      super-productivity
      orca-slicer
      ;
    inherit (pkgs.jetbrains) idea-ultimate;
    flatpak-chrome-alias = (
      pkgs.writeShellScriptBin "flatpak-chrome-alias" "flatpak run com.google.Chrome $@"
    );
    inherit (self.packages.${pkgs.system}) nautilus-thumbnailer-stl;
  };
}
