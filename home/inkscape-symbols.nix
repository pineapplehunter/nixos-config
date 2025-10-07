{
  config,
  lib,
  pkgs,
  ...
}:
let
  icons = pkgs.fetchFromGitHub {
    owner = "PanderMusubi";
    repo = "inkscape-open-symbols";
    rev = "48fc83b28704a52ab5dfabf9141a6fd8cf5ab6b2";
    hash = "sha256-JOZkMHpXqducO9Eja8D/yLiNquTevg8g5g8/rXy39g0=";
  };
  icons-extracted = pkgs.runCommand "inkscape-open-symbols-extracted" { } ''
    mkdir -p "$out"
    find ${icons} -type f -name "*.svg" -exec mv {} "$out" \;
  '';
in
{
  config.home.activation.inkscape-icons =
    let
      symbols-path = "${config.home.homeDirectory}/.var/app/org.inkscape.Inkscape/config/inkscape/symbols";
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [[ -d "${symbols-path}" ]]; then
        rm -f $VERBOSE_ARG "${symbols-path}/inkscape-open-symbols"
        ln -s $VERBOSE_ARG "${icons-extracted}" "${symbols-path}/inkscape-open-symbols"
      fi
    '';
}
