{
  copyDesktopItems,
  makeDesktopItem,
  stdenvNoCC,
  writeShellScript,
}:
let
  script = writeShellScript "google-calendar-open" ''
    xdg-open "https://calendar.google.com"
  '';
in
stdenvNoCC.mkDerivation {
  name = "google-calendar-open";
  nativeBuildInputs = [ copyDesktopItems ];
  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    cp ${script} google-calendar-open
    cp ${./icon.svg} google-calendar-open.svg
    install -Dt "$out/bin" google-calendar-open
    install -Dt "$out/share/icons/hicolor/scalable/apps" google-calendar-open.svg

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "google-calendar-open";
      desktopName = "Google Calendar";
      exec = "google-calendar-open";
      icon = "google-calendar-open";
      comment = "Open Google Calendar";
      categories = [ "Office" ];
    })
  ];
}
