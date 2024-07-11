{ pkgs, self, ... }:
{
  environment.systemPackages =
    (with pkgs; [
      blender
      webcord
      slack
      curl-http3
      jujutsu
      vivado
      jetbrains.idea-ultimate
      (writeShellScriptBin "flatpak-chrome-alias" "flatpak run com.google.Chrome $@")
      nixos-artwork-wallpaper
      ghidra
      wineWow64Packages.wayland
      winetricks
      jdk
      super-productivity
      android-studio
      orca-slicer
      (ventoy-full.override {
        defaultGuiType = "gtk3";
        withGtk3 = true;
      })

      lean4
    ])
    ++ (with self.packages.${pkgs.system}; [ nautilus-thumbnailer-stl ]);
}
