{ inputs, lib, ... }:
let
  overlayCombined = final: prev:
    let
      callOverlay = file: import file { inherit final prev inputs; };
      genOverlays = overlays: lib.attrsets.mergeAttrsList (map callOverlay overlays);
      removeDesktopEntry = package: {
        ${package} = final.symlinkJoin rec {
          inherit (prev.${package}) pname version;
          name = "${pname}-no-dekstop-${version}";
          paths = [ prev.${package} ];
          postBuild = ''
            rm -rfv $out/share/applications
          '';
        };
      };
      genRemoveDesktopEntries = packages: lib.attrsets.mergeAttrsList (map removeDesktopEntry packages);
    in
    (genOverlays [
      ./nixos-artwork-wallpaper.nix
      # ./blender.nix
      ./curl-http3.nix
      ./flatpak.nix
      ./android-studio.nix
    ])
    // (genRemoveDesktopEntries [ "julia" "btop" "htop" "helix"  ])
    // {
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
