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

      genOverlays = { overlayFiles ? [ ], removeDesktops ? [ ] }:
        (importOverlayFileList overlayFiles)
        // (removeDesktopEntryList removeDesktops);
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
