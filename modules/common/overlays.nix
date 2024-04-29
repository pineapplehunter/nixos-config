{ inputs, config, ... }:
with inputs; {
  nixpkgs.overlays = [
    nix-xilinx.overlay
    curl-http3.overlays.default
    (final: super: {
      nixos-artwork-wallpaper = final.callPackage ../../packages/nixos-artwork-wallpaper/package.nix { };
      python310 = super.python310.override {
        packageOverrides = pyself: pysuper: {
          py-slvs = pyself.callPackage ../../packages/python/py-slvs.nix { };
        };
      };
      blender = final.symlinkJoin {
        pname = "${super.blender.pname}-patched";
        inherit (super.blender) name version;
        paths = [ super.blender ];
        nativeBuildInputs = with final; [
          makeWrapper
          python310Packages.wrapPython
        ];
        pythonPath = with final.python310Packages; [ numpy requests py-slvs ];
        postBuild = ''
          rm $out/bin/blender
          mv $out/bin/.blender-wrapped $out/bin/blender

          buildPythonPath "$pythonPath"
          wrapProgram $out/bin/blender \
            --prefix PATH : $program_PATH \
            --prefix PYTHONPATH : "$program_PYTHONPATH" \
            --add-flags "--python-use-system-env"
        '';
      };

      gnome = super.gnome // {
        gnome-settings-daemon = super.gnome.gnome-settings-daemon.overrideAttrs (old: {
          # I don't need sleep notifications!
          postPatch = (old.postPatch or "") + ''
            substituteInPlace plugins/power/gsd-power-manager.c \
              --replace-fail "show_sleep_warning (manager);" "if(0) show_sleep_warning (manager);"
          '';
        });
      };

      ibus-engines = super.ibus-engines // {
        mozc = super.ibus-engines.mozc.overrideAttrs (old:{
          deps = old.deps.overrideAttrs {
            outputHash = "sha256-ToBLVJpAQErL/P1bfWJca2FjhDW5XTrwuJQLquwlrhA=";
          };
        });
      };
    })
  ];
}
