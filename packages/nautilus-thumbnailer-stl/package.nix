{
  fetchFromGitHub,
  lib,
  perl,
  povray,
  stdenv,
  stl2pov,
}:

stdenv.mkDerivation {
  pname = "nautilus-thumbnailer-stl";
  version = "0-unstable-2021-03-15";

  src = fetchFromGitHub {
    owner = "Spiritdude";
    repo = "Nautilus_Thumbnailer_STL";
    rev = "9da4e6e1675c8d49b53b184c365d037990db6e96";
    hash = "sha256-WkBfPdvyRngDhYh6oCUpE5+T8/0LaYvBtrrR0R9E5hE=";
  };

  buildInputs = [ perl ];

  installPhase = ''
    runHook preInstall

    substituteInPlace stl.thumbnailer \
      --replace-fail "/usr/local" "$out"

    substituteInPlace stl2png.pl \
      --replace-fail "povray" "${lib.getExe povray}" \
      --replace-fail "stl2pov" "${lib.getExe stl2pov}"

    install -m 755 -Dt $out/bin stl2png.pl
    install -m 644 -Dt $out/share/mime/packages stl.xml
    install -m 644 -Dt $out/share/thumbnailers stl.thumbnailer

    runHook postInstall
  '';
}
