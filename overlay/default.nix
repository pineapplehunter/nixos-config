{
  inputs,
  lib,
  ...
}:
rec {
  default = lib.composeManyExtensions [
    stable
    custom
    mozc
    removeDesktop
  ];

  removeDesktop =
    final: prev:
    let
      removeDesktopEntry =
        package:
        let
          inherit (package) version;
          pname = "${package.pname}-no-desktop";
        in
        final.runCommand "${pname}-${version}"
          {
            passthru = {
              inherit version pname;
              original = package;
            };
            preferLocalBuild = true;
          }
          ''
            cp -srL --no-preserve=mode ${package} $out
            rm -rfv $out/share/applications
          '';
    in
    {
      julia = removeDesktopEntry prev.julia;
      btop = removeDesktopEntry prev.btop;
      htop = removeDesktopEntry prev.htop;
      helix = removeDesktopEntry prev.helix;
      yazi = removeDesktopEntry prev.yazi;
    };

  custom = final: prev: {

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
  };

  stable =
    final: prev:
    let
      pkgs-stable = import inputs.nixpkgs-stable { inherit (final) system; };
    in
    {
      inherit (pkgs-stable) ;
    };

  mozc =
    final: prev:
    let
      mozc-package =
        name:
        let
          shard = builtins.substring 0 2 name;
        in
        final.callPackage (
          inputs.nixpkgs-pineapplehunter-mozc + /pkgs/by-name/${shard}/${name}/package.nix
        ) { };
    in
    {
      # mozc stuff
      jp-zip-codes = mozc-package "jp-zip-codes";
      merge-ut-dictionaries = mozc-package "merge-ut-dictionaries";
      jawiki-all-titles-in-ns0 = mozc-package "jawiki-all-titles-in-ns0";
      mozcdic-ut-jawiki = mozc-package "mozcdic-ut-jawiki";
      mozcdic-ut-personal-names = mozc-package "mozcdic-ut-personal-names";
      mozcdic-ut-place-names = mozc-package "mozcdic-ut-place-names";
      mozcdic-ut-sudachidict = mozc-package "mozcdic-ut-sudachidict";
      mozcdic-ut-alt-cannadic = mozc-package "mozcdic-ut-alt-cannadic";
      mozcdic-ut-edict2 = mozc-package "mozcdic-ut-edict2";
      mozcdic-ut-neologd = mozc-package "mozcdic-ut-neologd";
      mozcdic-ut-skk-jisyo = mozc-package "mozcdic-ut-skk-jisyo";
      mozc = mozc-package "mozc";
      ibus-engines = prev.ibus-engines // rec {
        mozc = mozc-package "mozc";
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
}
