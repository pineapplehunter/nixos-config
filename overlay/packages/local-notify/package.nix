{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  dbus,
  nss_wrapper,
}:

let
  python = python3.withPackages (ps: [
    ps.dbus-next
    ps.mcp
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "local-notify";
  version = "1.0.0";

  src = ./src;
  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ dbus ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    printf 'test:x:%s:%s:test:/tmp:/bin/sh\n' "$(id -u)" "$(id -g)" > "$TMPDIR/passwd"
    printf 'test:x:%s:\n' "$(id -g)" > "$TMPDIR/group"
    NSS_WRAPPER_PASSWD="$TMPDIR/passwd" \
    NSS_WRAPPER_GROUP="$TMPDIR/group" \
    LD_PRELOAD="${nss_wrapper}/lib/libnss_wrapper.so" \
    LOCAL_NOTIFY_TEST_BUS=1 \
      dbus-run-session --config-file=${dbus}/share/dbus-1/session.conf -- \
      ${python}/bin/python3 -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 notification.py "$out/libexec/local-notify/notification.py"
    install -Dm644 local-notify.py "$out/libexec/local-notify/local-notify.py"
    install -Dm644 local-notifyd.py "$out/libexec/local-notify/local-notifyd.py"
    install -Dm644 notification_mcp.py "$out/libexec/local-notify/notification_mcp.py"
    makeWrapper ${python}/bin/python3 "$out/bin/local-notify" \
      --add-flags "$out/libexec/local-notify/local-notify.py"
    makeWrapper ${python}/bin/python3 "$out/bin/local-notifyd" \
      --add-flags "$out/libexec/local-notify/local-notifyd.py"
    makeWrapper ${python}/bin/python3 "$out/bin/local-notify-mcp" \
      --add-flags "$out/libexec/local-notify/notification_mcp.py"
    runHook postInstall
  '';

  meta = {
    description = "Host Discord notification MCP server and compatible D-Bus CLI";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "local-notify";
  };
}
