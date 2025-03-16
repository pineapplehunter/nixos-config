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
    libfprint-tod =
      assert prev.libfprint-tod.version == "1.90.7+git20210222+tod1";
      prev.libfprint-tod.overrideAttrs (old: rec {
        version = "1.94.9+tod1";
        src = final.fetchFromGitLab {
          domain = "gitlab.freedesktop.org";
          owner = "3v1n0";
          repo = "libfprint";
          rev = "v${version}";
          hash = "sha256-xkywuFbt8EFJOlIsSN2hhZfMUhywdgJ/uT17uiO3YV4=";
        };
        mesonFlags = old.mesonFlags ++ [
          "-Dudev_rules_dir=${placeholder "out"}/lib/udev/rules.d"
        ];
        postPatch = ''
          patchShebangs \
            ./libfprint/tod/tests/*.sh \
            ./tests/*.py \
            ./tests/*.sh \
        '';
      });
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
