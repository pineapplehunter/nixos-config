{ inputs, config, ... }:
with inputs; {
  nixpkgs.overlays = [
    nix-xilinx.overlay
    curl-http3.overlays.default
    rust-overlay.overlays.default
    (final: super: {
      nixos-artwork-wallpaper = final.callPackage ../../packages/nixos-artwork-wallpaper/package.nix { };
      # nix = config.nix.package;
      # haskellPackages = super.haskellPackages.override {
      #   overrides = hsFinal: hsPrev: {
      #     cachix = hsPrev.cachix.override {
      #       nix = config.nix.package;
      #     };
      #   };
      # };
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
      fprintd = super.fprintd.overrideAttrs {
        postPatch = ''
          patchShebangs \
            po/check-translations.sh \
            tests/unittest_inspector.py

          # Stop tests from failing due to unhandled GTasks uncovered by GLib 2.76 bump.
          # https://gitlab.freedesktop.org/libfprint/fprintd/-/issues/151
          substituteInPlace tests/fprintd.py \
            --replace "env['G_DEBUG'] = 'fatal-criticals'" ""
          substituteInPlace tests/meson.build \
            --replace "'G_DEBUG=fatal-criticals'," ""

          # TODO: this is a temporary fix
          # Stop pam tests from failing with timeout
          substituteInPlace tests/pam/meson.build \
            --replace-fail "'test_pam_fprintd'," ""
        '';
      };
      fprintd-tod = (final.fprintd.override {
        libfprint = final.libfprint-tod;
      }).overrideAttrs
        {
          pname = "fprintd-tod";
        };
      libfprint-tod = final.libfprint.overrideAttrs rec {
        pname = "libfprint-tod";
        version = "1.94.6";

        src = final.fetchFromGitLab {
          domain = "gitlab.freedesktop.org";
          owner = "3v1n0";
          repo = "libfprint";
          rev = "v${version}+tod1";
          sha256 = "sha256-Ce56BIkuo2MnDFncNwq022fbsfGtL5mitt+gAAPcO/Y=";
        };

        postPatch = ''
          patchShebangs ./tests/*.py ./tests/*.sh ./libfprint/tod/tests/*.sh
        '';
      };

      gnome-console = super.gnome-console.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          (final.fetchpatch {
            url = "https://gitlab.gnome.org/GNOME/console/-/commit/7a02b32ca4efed6db74fd2e4f4c567e30493b968.patch";
            hash = "sha256-4TjlSgLlIELTTjSuz7HT6GMIL4lqsLtKVH9YtXsB2RQ=";
          })
        ];
      });
    })
  ];
}
