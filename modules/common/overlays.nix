{ pkgs, inputs, ... }: with inputs;{
  nixpkgs.overlays = [
    nix-xilinx.overlay
    curl-http3.overlays.default
    rust-overlay.overlays.default
    (final: super: {
      devenv = devenv.packages.${final.system}.devenv;
      julia = final.symlinkJoin {
        name = "julia";
        paths = [ super.julia ];
        buildInputs = [ final.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/julia \
            --set-default PYTHON "${final.python3.withPackages (ps: with ps;[sympy numpy])}/bin/python3"
        '';
      };
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
      f5vpn = pkgs.callPackage ../../f5vpn-nix/f5vpn/f5vpn.nix { };
      helix = super.helix.overrideAttrs (old: {
        patches = [ ./formatter.patch ];
      });
    })
  ];
}
