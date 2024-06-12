{ lib
, fetchFromGitHub
, stdenv
, python3
}:

# https://www.reddit.com/r/3Dprinting/comments/132lesb/3mf_thumbnails_on_linux/

stdenv.mkDerivation {
  pname = "nautilus-thumbnailer-3mf";
  version = "0.1.0";

  dontUnpack = true;

  buildInputs = [ python3 ];

  installPhase = ''
    runHook preInstall

    mkdir -pv $out/{share/thumbnailers,bin}
    cp -v ${./3mf.thumbnailer} $out/share/thumbnailers/3mf.thumbnailer
    cp -v ${./3mf2png.py} $out/bin/3mf2png.py

    chmod +x "$out/bin/3mf2png.py"
    substituteInPlace $out/share/thumbnailers/3mf.thumbnailer \
      --replace-fail "@program@" "$out/bin/3mf2png.py"

    runHook postInstall
  '';
}
