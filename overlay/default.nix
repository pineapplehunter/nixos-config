{
  inputs,
  lib,
  ...
}:
rec {
  default = lib.composeManyExtensions [
    platformSpecificOverlay
    global
    custom-packages
  ];

  global = final: prev: {
    # add support for http3
    curl-http3 = prev.curl.override {
      http3Support = true;
      openssl = prev.quictls;
    };

    # Fix issue: slow startup time.  Reason unknown (did not search).
    flatpak = prev.flatpak.overrideAttrs (old: {
      postPatch =
        (old.postPatch or "")
        + ''
          substituteInPlace common/flatpak-run.c \
            --replace-fail "if (!sandboxed && !(flags & FLATPAK_RUN_FLAG_NO_DOCUMENTS_PORTAL))" "" \
            --replace-fail "add_document_portal_args (bwrap, app_id, &doc_mount_path);" ""
        '';
    });

    # Faster builds when using remote builds
    android-studio = prev.android-studio.overrideAttrs {
      preferLocalBuild = true;
    };

    # Remove sleep notification.  The notification wakes up the screen
    # after dimming.
    gnome-settings-daemon = prev.gnome-settings-daemon.overrideAttrs (old: {
      # I don't need sleep notifications!
      postPatch =
        (old.postPatch or "")
        + ''
          substituteInPlace plugins/power/gsd-power-manager.c \
            --replace-fail "show_sleep_warnings = TRUE" "show_sleep_warnings = FALSE"
        '';
    });

    # Fix issue: non-standard version representation
    nix-search-cli = inputs.nix-search-cli.packages.${final.system}.default.overrideAttrs (old: {
      version = lib.head (lib.match ''[^0-9]*([0-9\.]+).*'' old.version);
      # supress warning
      inherit (old) src;
    });

    # Fix issue: slow input
    # https://github.com/ghostty-org/ghostty/issues/7724
    # https://github.com/ghostty-org/ghostty/discussions/7720#discussioncomment-13608668
    ghostty = prev.ghostty.overrideAttrs {
      preBuild = ''
        shopt -s globstar
        sed -i 's/^const xev = @import("xev");$/const xev = @import("xev").Epoll;/' **/*.zig
        shopt -u globstar
      '';
    };
  };

  custom-packages =
    final: prev:
    prev.lib.packagesFromDirectoryRecursive {
      inherit (final) callPackage;
      directory = ../packages;
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
