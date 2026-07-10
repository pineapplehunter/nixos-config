{
  inputs,
  config,
  lib,
  ...
}:
let
  inherit (config.flake) overlays;
in
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          inputs.nixgl.overlays.default
          overlays.default
        ];
      };
    };

  flake.overlays = {
    default = lib.composeManyExtensions [
      overlays.global
      overlays.custom-packages
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
      nix-search-cli =
        inputs.nix-search-cli.packages.${final.stdenv.hostPlatform.system}.default.overrideAttrs
          (old: {
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
            rev = "39ae9d32d8936e539c2f4ca0042fc31fcf0068a1";
            hash = "sha256-OEgql1Wj79EkoGZ/ZgmFVwMmCgLIhukqehCs/Gg7dLA=";
          };
          cargoDeps = final.rustPlatform.fetchCargoVendor {
            inherit (finalAttrs) src pname version;
            hash = "sha256-J6Qu8FFlp3PMTm0M/XT4TqQPaqH57TLBPhQE1Y5hdjg=";
          };
          doInstallCheck = false;
        }
      );

      tpm2-tools = prev.tpm2-tools.override {
        tpm2-tss = final.tpm2-tss.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            (final.fetchpatch {
              name = "add-nuvoton-certs.patch";
              url = "https://github.com/pineapplehunter/tpm2-tss/commit/6a9adcac623ffcff6bb08fb2c06fa7a6390546f4.patch";
              hash = "sha256-NSJ+NTOK3EJMWe1pf6Tsm26th34VczTD56xldWll1Aw=";
            })
          ];
        });
      };

      opencode = prev.opencode.overrideAttrs (old: {
        patches = [
          ./opencode-elapsed.patch
        ];
      });

      ibus-engines = prev.ibus-engines // {
        mozc = final.ibus-mozc;
        mozc-ut = final.ibus-mozc.override { mozc = final.mozc-ut; };
      };

      # march=arrowlake build
      # https://www.reddit.com/r/NixOS/comments/1b77j9i/build_with_marchnative_and_etc/
      linux_latest_arrowlake = prev.linux_latest.overrideAttrs (old: {
        env = (old.env or { }) // {
          KCFLAGS = "-march=arrowlake -mtune=arrowlake";
        };
      });
      # march=tigerlake build
      linux_latest_tigerlake = prev.linux_latest.overrideAttrs (old: {
        env = (old.env or { }) // {
          KCFLAGS = "-march=tigerlake -mtune=tigerlake";
        };
      });
      # march=znver1 build
      linux_latest_znver1 = prev.linux_latest.overrideAttrs (old: {
        env = (old.env or { }) // {
          KCFLAGS = "-march=znver1 -mtune=znver1";
        };
      });
    };

    custom-packages =
      final: prev:
      prev.lib.packagesFromDirectoryRecursive {
        inherit (final) callPackage;
        directory = ./packages;
      };
  };
}
