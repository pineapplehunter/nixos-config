{ stdenv, fetchurl, rpmextract, autoPatchelfHook, qt5 }:
let
  src-rpm = fetchurl {
    url = "https://huskyonnet-ns.uw.edu/public/download/linux_f5vpn.x86_64.rpm";
    hash = "sha256-wrZ8vE7i6JUkhteWCc6B6ycgscAff46NGrMe87opAw4=";
  };
in
with qt5; stdenv.mkDerivation {
  pname = "f5vpn";
  version = "0.0.0";
  buildInputs = [ qtbase ];
  nativeBuildInputs = [ rpmextract autoPatchelfHook wrapQtAppsHook ];
  unpackPhase = ''
    rpmextract ${src-rpm}
  '';

  dontPatch = true;
  dontConfigure = true;
  # dontBuild = true;
  # set this to stop messing with rpath
  # https://github.com/NixOS/patchelf/issues/99
  dontStrip = true;

  outputs = [ "out" "lib" ];

  preBuild = ''
    addAutoPatchelfSearchPath $lib/lib
  '';

  installPhase = ''
    install -D ./opt/f5/vpn/f5vpn $out/bin/f5vpn
    install -D ./opt/f5/vpn/svpn $out/bin/svpn
    install -D ./opt/f5/vpn/tunnelserver $out/bin/tunnelserver
    cp -r ./opt/f5/vpn/lib $lib
  '';

}
