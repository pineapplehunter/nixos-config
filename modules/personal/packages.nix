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
      ghidra
      winetricks
      jdk
      super-productivity
      android-studio
      orca-slicer
      lean4;
    ventoy-custom = (pkgs.ventoy-full.override {
      defaultGuiType = "gtk3";
      withGtk3 = true;
    });
    inherit (pkgs.jetbrains) idea-ultimate;
    inherit (pkgs.wineWow64Packages) wayland;
    flatpak-chrome-alias = (pkgs.writeShellScriptBin "flatpak-chrome-alias" "flatpak run com.google.Chrome $@");
    inherit (self.packages.${pkgs.system}) nautilus-thumbnailer-stl;
  };
}
