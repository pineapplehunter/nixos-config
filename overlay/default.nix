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
    # Fix issue: slow startup time.  Reason unknown (did not search).
    flatpak = prev.flatpak.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace common/flatpak-run.c \
          --replace-fail "if (!sandboxed && !(flags & FLATPAK_RUN_FLAG_NO_DOCUMENTS_PORTAL))" "" \
          --replace-fail "add_document_portal_args (bwrap, app_id, &doc_mount_path);" ""
      '';
    });

    # Remove sleep notification.  The notification wakes up the screen
    # after dimming.
    gnome-settings-daemon = prev.gnome-settings-daemon.overrideAttrs (old: {
      # I don't need sleep notifications!
      postPatch = (old.postPatch or "") + ''
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

    # Add capability support
    # https://github.com/eza-community/eza/pull/1624
    eza = prev.eza.overrideAttrs (
      finalAttrs: prevAttrs: {
        version = "0-custom";
        src = final.fetchFromGitHub {
          owner = "pineapplehunter";
          repo = "eza";
          rev = "9ce6f250358df0ced6d2ca96ca02c4227e54bed4";
          hash = "sha256-UB9b7jKiqxQDiKqDyLFn6Q2nq77ph9kYHTKjPuV8/Zw=";
        };
        cargoDeps = final.rustPlatform.fetchCargoVendor {
          inherit (finalAttrs) src pname version;
          hash = "sha256-uieSKyhdwREMKDs4hurHcBm/W6MYmMUceFPaNIxTYes=";
        };
      }
    );

    # Cmake4 related build failures.
    # temporary fix to build the packages.
    # https://github.com/NixOS/nixpkgs/issues/445447
    qgnomeplatform = prev.qgnomeplatform.overrideAttrs (old: {
      env.CMAKE_POLICY_VERSION_MINIMUM = "3.5";
    });
    qgnomeplatform-qt6 = prev.qgnomeplatform-qt6.overrideAttrs (old: {
      env.CMAKE_POLICY_VERSION_MINIMUM = "3.5";
    });
    julia = prev.julia.overrideAttrs (old: {
      env.CMAKE_POLICY_VERSION_MINIMUM = "3.5";
    });
    intel-graphics-compiler = prev.intel-graphics-compiler.overrideAttrs (old: {
      env.CMAKE_POLICY_VERSION_MINIMUM = "3.5";
    });
    libvdpau-va-gl = prev.libvdpau-va-gl.overrideAttrs (old: {
      env.CMAKE_POLICY_VERSION_MINIMUM = "3.5";
    });
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
