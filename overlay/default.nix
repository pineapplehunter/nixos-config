{
  inputs,
  self,
  lib,
}:
let
  stableOverlay =
    final: prev:
    let
      makeStable =
        packageName:
        let
          stablePkgs = inputs.nixpkgs-stable.legacyPackages.${final.system};
        in
        {
          ${packageName} = stablePkgs.${packageName};
        };
      makeStableList = packages: lib.attrsets.mergeAttrsList (map makeStable packages);
    in
    makeStableList [
      # "cargo-tauri"
      # "cargo-outdated"
      "elan"
    ];

  fileOverlay =
    final: prev:
    let
      mozc-package =
        shard: name:
        final.callPackage (
          inputs.nixpkgs-pineapplehunter-mozc + /pkgs/by-name/${shard}/${name}/package.nix
        ) { };
    in
    {
      inherit (self.packages.${final.system}) nixos-artwork-wallpaper;
      curl-http3 = prev.curl.override {
        http3Support = true;
        openssl = prev.quictls;
      };
      flatpak = prev.flatpak.overrideAttrs (old: {
        postPatch =
          (old.postPatch or "")
          + ''
            substituteInPlace common/flatpak-run.c \
              --replace-fail "if (!sandboxed && !(flags & FLATPAK_RUN_FLAG_NO_DOCUMENTS_PORTAL))" "" \
              --replace-fail "add_document_portal_args (bwrap, app_id, &doc_mount_path);" ""
          '';
      });
      android-studio = prev.android-studio.overrideAttrs {
        preferLocalBuild = true;
      };
      super-productivity = final.callPackage (
        inputs.nixpkgs-pineapplehunter-supprod + /pkgs/by-name/su/super-productivity/package.nix
      ) { };
      mqttx-cli = final.callPackage (
        inputs.nixpkgs-pineapplehunter-mqttx-cli + /pkgs/by-name/mq/mqttx-cli/package.nix
      ) { };
      gitify = final.callPackage (
        inputs.nixpkgs-pineapplehunter-gitify + /pkgs/by-name/gi/gitify/package.nix
      ) { };
      # blender =mozc
      #   let
      #     python = final.python311Packages;
      #     inherit (prev.blender) pname version;
      #   in
      #   final.symlinkJoin {
      #     name = "${pname}-wrapped-${version}";
      #     paths = [ prev.blender ];
      #     nativeBuildInputs = [
      #       final.makeWrapper
      #       python.wrapPython
      #     ];
      #     pythonPath = with python; [
      #       numpy
      #       requests
      #       py-slvs
      #     ];
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
          postPatch =
            (old.postPatch or "")
            + ''
              substituteInPlace plugins/power/gsd-power-manager.c \
                --replace-fail "show_sleep_warning (manager);" "if(0) show_sleep_warning (manager);"
            '';
        });
      };

      # mozc stuff
      jp-zip-codes = mozc-package "jp" "jp-zip-codes";
      merge-ut-dictionaries = mozc-package "me" "merge-ut-dictionaries";
      jawiki-all-titles-in-ns0 = mozc-package "ja" "jawiki-all-titles-in-ns0";
      mozcdic-ut-jawiki = mozc-package "mo" "mozcdic-ut-jawiki";
      mozcdic-ut-personal-names = mozc-package "mo" "mozcdic-ut-personal-names";
      mozcdic-ut-place-names = mozc-package "mo" "mozcdic-ut-place-names";
      mozcdic-ut-sudachidict = mozc-package "mo" "mozcdic-ut-sudachidict";
      mozcdic-ut-alt-cannadic = mozc-package "mo" "mozcdic-ut-alt-cannadic";
      mozcdic-ut-edict2 = mozc-package "mo" "mozcdic-ut-edict2";
      mozcdic-ut-neologd = mozc-package "mo" "mozcdic-ut-neologd";
      mozcdic-ut-skk-jisyo = mozc-package "mo" "mozcdic-ut-skk-jisyo";
      ibus-engines = prev.ibus-engines // rec {
        mozc = final.callPackage (
          inputs.nixpkgs-pineapplehunter-mozc + /pkgs/tools/inputmethods/ibus-engines/ibus-mozc/default.nix
        ) { };
        mozc-ut = mozc.override {
          dictionaries = builtins.attrValues {
            inherit (final)
              mozcdic-ut-alt-cannadic
              mozcdic-ut-edict2
              mozcdic-ut-jawiki
              mozcdic-ut-neologd
              mozcdic-ut-personal-names
              mozcdic-ut-place-names
              mozcdic-ut-skk-jisyo
              mozcdic-ut-sudachidict
              ;
          };
        };
      };
    };

  removeDesktopOverlay =
    final: prev:
    let
      removeDesktopEntry =
        packageName:
        let
          package = prev.${packageName};
          inherit (package) pname version;
        in
        {
          ${packageName} =
            final.runCommand "${pname}-no-desktop-${version}"
              {
                passthru.original = package;
                preferLocalBuild = true;
              }
              ''
                cp -srL --no-preserve=mode ${package} $out
                rm -rfv $out/share/applications
              '';
        };
      removeDesktopEntryList = packages: lib.attrsets.mergeAttrsList (map removeDesktopEntry packages);
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
