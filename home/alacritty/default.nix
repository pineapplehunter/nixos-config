{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (config.pineapplehunter) is-nixos;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  config.programs.alacritty = {
    enable = isLinux;
    package =
      let
        inherit (pkgs) alacritty makeWrapper nixgl;
        inherit (lib) getExe;
      in
      pkgs.symlinkJoin {
        name = "alacritty-wrapped-${alacritty.version}";
        paths = [ alacritty ];
        nativeBuildInputs = [ makeWrapper ];
        postBuild =
          if is-nixos then
            ''
              rm $out/bin/alacritty
              makeWrapper "${getExe alacritty}" "$out/bin/alacritty" \
                --set-default XCURSOR_THEME Adwaita \
                --inherit-argv0
            ''
          else
            ''
              rm $out/bin/alacritty
              makeWrapper "${getExe (nixgl.override { enable32bits = false; }).nixGLMesa}" "$out/bin/alacritty" \
                --set-default XCURSOR_THEME Adwaita \
                --add-flags "${getExe alacritty}" \
                --inherit-argv0
            '';
      };
    settings = lib.importTOML ./alacritty-config.toml;
  };

}
