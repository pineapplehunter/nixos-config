{ lib
, fetchFromGitHub
, buildPythonPackage
, pillow
}:

buildPythonPackage {
  pname = "gcode-thumbnailer";
  version = "0-unstable-2022-06-04";
  format = "none";

  src = fetchFromGitHub {
    owner = "ellensp";
    repo = "gcode-thumbnailer";
    rev = "9716043ffcb929be713643ce32afbfebc9cdd4ec";
    hash = "sha256-kh6VFiXNorevy5JyoPUaD7Tsq7FndHqcTGzC6gIt3DY=";
  };

  propagatedBuildInputs = [ pillow ];

  installPhase = ''
    runHook preInstall

    mkdir -pv $out/{share/thumbnailers,bin}
    cp -v gcode-with-thumbnail.thumbnailer $out/share/thumbnailers
    cp -v gcode-with-thumbnail-thumbnailer.py $out/bin
    
    chmod +x $out/bin/gcode-with-thumbnail-thumbnailer.py
    substituteInPlace $out/share/thumbnailers/gcode-with-thumbnail.thumbnailer \
      --replace-fail "gcode-with-thumbnail-thumbnailer.py" "$out/bin/gcode-with-thumbnail-thumbnailer.py"

    runHook postInstall
  '';
}
