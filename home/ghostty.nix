{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  inherit (config.pineapplehunter) isNixos;
in
{
  config.programs.ghostty = {
    enable = isLinux;
    package =
      if isNixos then
        pkgs.ghostty
      else
        let
          inherit (lib) getExe;
          inherit (pkgs) ghostty makeWrapper nixgl;
        in
        pkgs.symlinkJoin {
          name = "ghostty-wrapped-${ghostty.version}";
          paths = [ ghostty ];
          nativeBuildInputs = [ makeWrapper ];
          meta.mainProgram = "ghostty";
          postBuild = ''
            rm $out/bin/ghostty
            makeWrapper "${getExe (nixgl.override { enable32bits = false; }).nixGLMesa}" "$out/bin/ghostty" \
              --add-flags "${getExe ghostty}" \
          '';
        };
    settings = {
      font-feature = "-dlig";
      font-size = 10;
      gtk-titlebar = false;
      keybind = [
        "ctrl+shift+plus=increase_font_size:1"
        "ctrl+shift+equal=decrease_font_size:1"
        "ctrl+shift+0=reset_font_size"
        "ctrl+enter=unbind"
      ];
      theme = "Adwaita";
      window-inherit-working-directory = false;
      window-theme = "light";
      working-directory = "home";
    };
  };
}
