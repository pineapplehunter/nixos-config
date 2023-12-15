{ stdenv, fetchurl, rpmextract, autoPatchelfHook, gcc-unwrapped, glib, xorg, libglvnd, freetype, fontconfig, libxslt, libxml2, sqlite }:
let
  src-rpm = fetchurl {
    url = "https://huskyonnet-ns.uw.edu/public/download/linux_f5vpn.x86_64.rpm";
    hash = "sha256-wrZ8vE7i6JUkhteWCc6B6ycgscAff46NGrMe87opAw4=";
  };
in
stdenv.mkDerivation {
  pname = "f5vpn";
  version = "0.0.0";
  buildInputs = with xorg;[ gcc-unwrapped glib libX11 libXext libXrender libglvnd freetype fontconfig libXi libXcomposite libxslt libxml2 sqlite libSM libICE ];
  nativeBuildInputs = [ rpmextract autoPatchelfHook ];

  unpackPhase = ''
    rpmextract ${src-rpm}
  '';

  # dontPatch = true;
  # dontConfigure = true;
  # dontBuild = true;
  # set this to stop messing with rpath
  # https://github.com/NixOS/patchelf/issues/99
  # dontStrip = true;

  # outputs = [ "out" "lib" ];

  preBuild = ''
    addAutoPatchelfSearchPath $lib/lib
  '';

  # autoPatchelfIgnoreMissingDeps = [ "libQt5WebKitWidgets.so.5" "libQt5WebKit.so.5" ];

  installPhase = ''
    install -D ./opt/f5/vpn/f5vpn $out/bin/f5vpn
    install -D ./opt/f5/vpn/svpn $out/bin/svpn
    install -D ./opt/f5/vpn/tunnelserver $out/bin/tunnelserver

    # patchelf $out/bin/f5vpn \
    #   --replace-needed libicudata.so.55 libicudata.so \
    #   --replace-needed libcrypto.so.1.0.0 libcrypto.so.1.1 \
    #   --replace-needed libssl.so.1.0.0 libssl.so.1.1 \
    #   --replace-needed libicui18n.so.55 libicui18n.so \
    #   --replace-needed libicuuc.so.55 libicuuc.so \
    #   --replace-needed libQt5WebKitWidgets.so.5 libQt5WebKitWidgets.so \
    #   --replace-needed libQt5WebKit.so.5 libQt5WebKit.so

    # cp -r ./opt/f5/vpn/lib $lib
  '';

}
