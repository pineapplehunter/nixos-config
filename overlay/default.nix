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
          inputs.nix-xilinx.overlay
          inputs.agenix.overlays.default
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
            rev = "b2ead8a48777223c1aa50cd75ac49901c80d146b";
            hash = "sha256-7pcuaxga9ctlEsUhNSl32aiYPhkQtkqXBzR6Cs71dCM=";
          };
          cargoDeps = final.rustPlatform.fetchCargoVendor {
            inherit (finalAttrs) src pname version;
            hash = "sha256-o2lYnCTXyNrZVX+IWaAdmyxpvdEPy+TCltpJhXYDIkg=";
          };
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

      gnomeExtensions = prev.gnomeExtensions // {
        # https://github.com/joaophi/tailscale-gnome-qs/pull/45
        # https://github.com/tailscale-qs/tailscale-gnome-qs/issues/7
        tailscale-qs = prev.gnomeExtensions.tailscale-qs.overrideAttrs (old: {
          version = "0-custom";
          src = final.fetchFromGitHub {
            owner = "tailscale-qs";
            repo = "tailscale-gnome-qs";
            rootDir = "tailscale-gnome-qs@tailscale-qs.github.io";
            rev = "f1906cece38cbc5da2db835febb30b1cc0b675a7";
            hash = "sha256-BHlMSX+LFBm1hOEaOkApHxPgrTYDnglzK+0UxY6KOzI=";
          };
        });
      };
    };

    custom-packages =
      final: prev:
      prev.lib.packagesFromDirectoryRecursive {
        inherit (final) callPackage;
        directory = ./packages;
      };
  };
}
