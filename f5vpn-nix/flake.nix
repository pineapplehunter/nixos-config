{
  description = "F5CLI";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    f5cli-rpm = {
      url = "https://huskyonnet-ns.uw.edu/public/download/linux_f5cli.x86_64.rpm";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, f5cli-rpm }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in

    {
      packages.x86_64-linux.default = self.packages.x86_64-linux.f5cli;
      packages.x86_64-linux.f5cli = pkgs.stdenv.mkDerivation {
        pname = "f5vcli";
        version = "0.0.1";
        nativeBuildInputs = with pkgs;[ rpmextract ];
        buildInputs = with pkgs;[
          autoPatchelfHook
        ];
        unpackPhase = ''
          rpmextract ${f5cli-rpm}
        '';

        dontPatch = true;
        dontConfigure = true;
        # dontBuild = true;
        # set this to stop messing with rpath
        # https://github.com/NixOS/patchelf/issues/99
        dontStrip = true;

        preBuild = ''
          addAutoPatchelfSearchPath $out/lib
        '';

        installPhase = ''
          install -D ./usr/local/bin/f5fpc $out/bin/f5fpc
        '';

      };

      formatter.x86_64-linux = pkgs.nixpkgs-fmt;

      devShell.x86_64-linux = pkgs.mkShell {
        packages = with pkgs;[ rpmextract ];
      };
    };
}
