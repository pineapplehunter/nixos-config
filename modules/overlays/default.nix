{ inputs, lib, ... }:
let
  overlayCombined = final: prev:
    let
      callOverlay = file: import file { inherit final prev inputs; };
      genOverlays = overlays: (lib.attrsets.mergeAttrsList (map callOverlay overlays));
    in
    (genOverlays [
      ./nixos-artwork-wallpaper.nix
      ./blender.nix
      ./curl-http3.nix
      ./flatpak.nix
      ./android-studio.nix
    ]) // {
      gnome = prev.gnome // (genOverlays [
        ./gnome-settings-daemon.nix
      ]);
      ibus-engines = prev.ibus-engines // (genOverlays [
        ./mozc.nix
      ]);
    };
in
{
  nixpkgs.overlays = [
    inputs.nix-xilinx.overlay
    overlayCombined
  ];
}
