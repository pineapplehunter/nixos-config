{ inputs, self, lib }:
let
  overlayCombined = final: prev:
    let
      importOverlayFile = file: import file { inherit final prev inputs self; };
      importOverlayFileList = files:
        lib.attrsets.mergeAttrsList (map importOverlayFile files);

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

      makeStable = packageName:
        let
          stablePkgs = inputs.nixpkgs-stable.legacyPackages.${final.system};
        in
        {
          ${packageName} = stablePkgs.${packageName};
        };
      makeStableList = packages:
        lib.attrsets.mergeAttrsList (map makeStable packages);

      genOverlays = { overlayFiles ? [ ], removeDesktops ? [ ], stable ? [ ] }: lib.attrsets.mergeAttrsList [
        (importOverlayFileList overlayFiles)
        (removeDesktopEntryList removeDesktops)
        (makeStableList stable)
      ];
    in
    (genOverlays {
      overlayFiles = [
        ./nixos-artwork-wallpaper.nix
        # ./blender.nix
        ./curl-http3.nix
        ./flatpak.nix
        ./android-studio.nix
      ];
      removeDesktops = [
        "julia"
        "btop"
        "htop"
        "helix"
        "yazi"
      ];
      stable = [
        "fprintd"
        "fprintd-tod"
        # "blender"
      ];
    })
    // {
      gnome = prev.gnome // (genOverlays {
        overlayFiles = [
          ./gnome-settings-daemon.nix
        ];
      });
      ibus-engines = prev.ibus-engines // (genOverlays {
        overlayFiles = [
          ./mozc.nix
        ];
      });
    };
in
overlayCombined
