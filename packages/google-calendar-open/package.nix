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
    mkdir -p $out/bin
    cp ${script} $out/bin/google-calendar-open
    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "google-calendar-open";
      desktopName = "Google Calendar";
      exec = "google-calendar-open";
      icon = "org.gnome.Calendar";
      comment = "Open Google Calendar";
      categories = [ "Office" ];
    })
  ];
}
