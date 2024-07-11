{
  lib,
  fetchFromGitHub,
  stdenv,
  perl,
  povray,
  stl2pov,
  makeWrapper,
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

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ perl ];

  postPatch = ''
    substituteInPlace stl.thumbnailer \
      --replace-fail "/usr/local" "$out"
  '';

  installPhase = ''
    runHook preInstall

    mkdir -pv $out/{share/{thumbnailers,mime/packages},bin}
    cp -v stl.thumbnailer $out/share/thumbnailers
    cp -v stl2png.pl $out/bin
    cp -v stl.xml $out/share/mime/packages
    chmod +x $out/bin/stl2png.pl
    wrapProgram $out/bin/stl2png.pl \
      --prefix PATH : ${povray}/bin \
      --prefix PATH : ${stl2pov}/bin

    runHook postInstall
  '';
}
