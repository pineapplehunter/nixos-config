{ pkgs, self, ... }: {
  environment.systemPackages = with pkgs; [
    tectonic
    blender
    webcord
    slack
    curl-http3
    jujutsu
    vivado
    jetbrains.idea-ultimate
    (writeShellScriptBin "flatpak-chrome-alias"
      "flatpak run com.google.Chrome $@")
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
    self.packages.${pkgs.system}.nautilus-thumbnailer-stl
    self.packages.${pkgs.system}.nautilus-thumbnailer-3mf
    self.packages.${pkgs.system}.typst-thumbnailer

    sqlx-cli
    cargo-tauri
    cargo-expand
    cargo-fuzz
    cargo-watch
    cargo-bloat
    cargo-outdated
    trunk
    gnome.gnome-terminal

    lean4
  ];
}
