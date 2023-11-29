{ inputs }: { pkgs, ... }: {
  nixpkgs.overlays = [
    inputs.nix-xilinx.overlay
    inputs.curl-http3.overlays.default
    inputs.rust-overlay.overlays.default
    (final: super: {
      devenv = inputs.devenv.packages.${final.system}.devenv;
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
        pname = "nixos-wallpapers";
        version = "1.0.0";
        src = inputs.nixos-artwork;
        unpackPhase = "true";
        buildPhase = "true";
        installPhase = ''
          mkdir -pv $out/share/backgrounds/nixos
          realpath ${src}
          cp -v ${src}/wallpapers/*.png $out/share/backgrounds/nixos
        '';
      };
    })
  ];
}
