{
  flake.nixosModules.personal =
    { pkgs, ... }:
    let
      flatpak-chrome-alias = pkgs.writeShellScriptBin "flatpak-chrome-alias" "flatpak run com.google.Chrome $@";
    in
    {
      environment.systemPackages = [
        pkgs.blender
        pkgs.jujutsu
        pkgs.nautilus-thumbnailer-stl
        pkgs.orca-slicer
        pkgs.vivado
        flatpak-chrome-alias
      ];
    };
}
