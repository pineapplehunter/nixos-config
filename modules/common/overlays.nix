{ inputs, ... }:
{
  nixpkgs.overlays = [
    inputs.nix-xilinx.overlay
    (final: prev: {
      nixos-artwork-wallpaper = final.callPackage ../../packages/nixos-artwork-wallpaper/package.nix { };
      python310 = prev.python310.override {
        packageOverrides = pyself: pysuper: {
          py-slvs = pyself.callPackage ../../packages/python/py-slvs.nix { };
        };
      };
      # blender =
      #   let
      #     python = final.python311Packages;
      #     inherit (final.blender) pname version;
      #   in
      #   final.symlinkJoin {
      #     name = "${pname}-wrapped-${version}";
      #     paths = [ super.blender ];
      #     nativeBuildInputs = [
      #       final.makeWrapper
      #       python.wrapPython
      #     ];
      #     pythonPath = with python; [ numpy requests py-slvs ];
      #     postBuild = ''
      #       rm $out/bin/blender
      #       mv $out/bin/.blender-wrapped $out/bin/blender

      #       buildPythonPath "$pythonPath"
      #       wrapProgram $out/bin/blender \
      #         --prefix PATH : $program_PATH \
      #         --prefix PYTHONPATH : "$program_PYTHONPATH" \
      #         --add-flags "--python-use-system-env"
      #     '';
      #   };

      gnome = prev.gnome // {
        gnome-settings-daemon = prev.gnome.gnome-settings-daemon.overrideAttrs (old: {
          # I don't need sleep notifications!
          postPatch = (old.postPatch or "") + ''
            substituteInPlace plugins/power/gsd-power-manager.c \
              --replace-fail "show_sleep_warning (manager);" "if(0) show_sleep_warning (manager);"
          '';
        });
      };

      ibus-engines = prev.ibus-engines // {
        mozc = inputs.nixpkgs-pineapplehunter.legacyPackages.x86_64-linux.ibus-engines.mozc;
      };

      curl-http3 = prev.curl.override {
        http3Support = true;
        openssl = prev.quictls;
      };

      flatpak = prev.flatpak.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace common/flatpak-run.c \
            --replace-fail "if (!sandboxed && !(flags & FLATPAK_RUN_FLAG_NO_DOCUMENTS_PORTAL))" "" \
            --replace-fail "add_document_portal_args (bwrap, app_id, &doc_mount_path);" ""
        '';
      });

      android-studio = prev.android-studio.overrideAttrs {
        preferLocalBuild = true;
      };

      # python3 = super.python312;

      # inherit (nixpkgs-stable.legacyPackages.${super.system}) fprintd libfprint libfprint-tod fprintd-tod;
      # inherit (nixpkgs-stable.legacyPackages.${super.system}) ibus;
    })
  ];
}
