{
  fetchFromGitHub,
  stdenv,
}:

stdenv.mkDerivation {
  pname = "stl2pov";
  version = "0-unstable-2018-12-12";

  src = fetchFromGitHub {
    owner = "Spiritdude";
    repo = "stl2pov";
    rev = "77f1bd380248aab87734cf68c3942827ec8b5bab";
    hash = "sha256-lgN0G8YQHLUnALr8DnpEwEdfA6tmsgIovhRT/fwgo0M=";
  };

  outputs = [
    "out"
    "man"
    "doc"
  ];

  makeFlags = [
    "BINDIR=${placeholder "out"}/bin"
    "MANDIR=${placeholder "man"}/man"
    "DOCSDIR=${placeholder "doc"}/share/doc/stl2pov"
  ];

  postPatch = ''
    substituteInPlace Makefile GNUmakefile \
      --replace-fail "id -u" "echo 0"
  '';

  meta.mainProgram = "stl2pov";
}
