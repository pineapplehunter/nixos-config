{
  lib,
  stdenvNoCC,
  ghostty,
  ncurses,
  zig_0_15,
}:

stdenvNoCC.mkDerivation {
  pname = "ghostty-terminfo";
  inherit (ghostty) version src;

  nativeBuildInputs = [
    ncurses
    zig_0_15
  ];

  postPatch = ''
    cp ${./generate.zig} generate.zig
  '';

  buildPhase = ''
    runHook preBuild

    zig run generate.zig > ghostty.terminfo

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/terminfo"
    tic -x -o "$out/share/terminfo" ghostty.terminfo

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ ncurses ];
  installCheckPhase = ''
    TERMINFO="$out/share/terminfo" infocmp xterm-ghostty >/dev/null
  '';

  meta = {
    description = "Ghostty terminal information database";
    homepage = "https://ghostty.org";
    license = lib.licenses.mit;
    inherit (ghostty.meta) maintainers platforms;
  };
}
