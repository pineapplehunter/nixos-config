{ inputs, config, ... }: with inputs;{
  nixpkgs.overlays = [
    nix-xilinx.overlay
    curl-http3.overlays.default
    rust-overlay.overlays.default
    (final: super: {
      nixos-artwork-wallpaper = final.stdenv.mkDerivation rec {
        name = "nixos-wallpapers";
        src = nixos-artwork;
        unpackPhase = "true";
        buildPhase = "true";
        installPhase = ''
          mkdir -pv $out/share/backgrounds/nixos
          realpath ${src}
          cp -v ${src}/wallpapers/*.png $out/share/backgrounds/nixos
        '';
      };
      helix = super.helix.overrideAttrs (old: {
        patches = [ ./helix.formatter.patch ];
      });

      ibus-engines = super.ibus-engines // {
        mozc = super.ibus-engines.mozc.overrideAttrs (old: {
          postUnpack = "";
          postPatch = ''
            substituteInPlace src/gyp/common.gypi \
              --replace "'-stdlib=libc++'," "" \
              --replace "-lc++" "-lstdc++"
            pushd src/third_party/abseil-cpp/absl/strings/internal/str_format
            cp extension.h extension.h_bak
            cat <(echo "#include <stdint.h>") extension.h_bak > extension.h # prepend stdint
            popd
          '';
        });
      };
      nix = config.nix.package;
      # haskellPackages = super.haskellPackages.override {
      #   overrides = hsFinal: hsPrev: {
      #     cachix = hsPrev.cachix.override {
      #       nix = config.nix.package;
      #     };
      #   };
      # };
    })
  ];
}
