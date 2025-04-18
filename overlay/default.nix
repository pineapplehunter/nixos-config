{
  inputs,
  lib,
  ...
}:
rec {
  default = lib.composeManyExtensions [
    platformSpecificOverlay
    custom
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
    nix-search-cli = inputs.nix-search-cli.packages.${final.system}.default.overrideAttrs (old: {
      # fix non-standard version representation
      version = builtins.head (builtins.match ''[^0-9]*([0-9\.]+).*'' old.version);
    });

    # https://github.com/NixOS/nixpkgs/pull/397276
    gitlab-ci-local = prev.gitlab-ci-local.overrideAttrs {
      postInstall = ''
        NODE_MODULES=$out/lib/node_modules/gitlab-ci-local/node_modules
        cp $NODE_MODULES/re2/build/Release/re2.node re2.node
        strip -x re2.node
        rm -rf $NODE_MODULES/re2/build
        install -Dt $NODE_MODULES/re2/build/Release re2.node
        rm -rf $NODE_MODULES/{node-gyp/gyp,re2/vendor}
      '';
    };

    stl2pov = final.callPackage ../packages/stl2pov { };
    nautilus-thumbnailer-stl = final.callPackage ../packages/nautilus-thumbnailer-stl { };
  };

  platformSpecificOverlay =
    final: prev:
    let
      # from https://discourse.nixos.org/t/nix-function-to-merge-attributes-records-recursively-and-concatenate-arrays/2030?u=pineapplehunter
      recursiveMergeAttrs =
        listOfAttrsets: lib.fold (attrset: acc: lib.recursiveUpdate attrset acc) { } listOfAttrsets;
    in
    recursiveMergeAttrs [
      (lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
        inherit (import inputs.nixpkgs-stable { inherit (prev) system; })
          ;
      })
      (lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin { })
    ];
}
