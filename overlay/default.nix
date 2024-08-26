{ inputs, self, lib }:
let
  stableOverlay = final: prev:
    let
      makeStable = packageName:
        let
          stablePkgs = inputs.nixpkgs-stable.legacyPackages.${final.system};
        in
        {
          ${packageName} = stablePkgs.${packageName};
        };
      makeStableList = packages:
        lib.attrsets.mergeAttrsList (map makeStable packages);
    in
    makeStableList [
      # "cargo-tauri"
      # "cargo-outdated"
      "elan"
    ];

  fileOverlay = final: prev:
    let
      importOverlayFile = file: import file { inherit final prev inputs self; };
      importOverlayFileList = files:
        lib.attrsets.mergeAttrsList (map importOverlayFile files);
    in
    (importOverlayFileList [
      ./nixos-artwork-wallpaper.nix
      # ./blender.nix
      ./curl-http3.nix
      ./flatpak.nix
      ./android-studio.nix
      ./super-productivity.nix
    ]) // {
      gnome = prev.gnome // (importOverlayFileList [
        ./gnome-settings-daemon.nix
      ]);
      ibus-engines = prev.ibus-engines // (importOverlayFileList [
        ./mozc.nix
      ]);
    };

  removeDesktopOverlay = final: prev:
    let
      removeDesktopEntry = packageName:
        let
          package = prev.${packageName};
          inherit (package) pname version;
        in
        {
          ${packageName} = final.runCommand "${pname}-no-desktop-${version}"
            {
              passthru.original = package;
              preferLocalBuild = true;
            }
            ''
              cp -srL --no-preserve=mode ${package} $out
              rm -rfv $out/share/applications
            '';
        };
      removeDesktopEntryList = packages:
        lib.attrsets.mergeAttrsList (map removeDesktopEntry packages);
    in
    removeDesktopEntryList [
      "julia"
      "btop"
      "htop"
      "helix"
      "yazi"
    ];

in
{
  inherit stableOverlay fileOverlay removeDesktopOverlay;
}
