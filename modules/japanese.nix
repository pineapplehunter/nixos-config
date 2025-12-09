{
  flake.nixosModules.japanese =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.pineapplehunter.japanese;
    in
    {
      options.pineapplehunter.japanese = {
        enable = lib.mkEnableOption "add japanese things";
        fonts.enable = lib.mkEnableOption "japanese font packages" // {
          default = true;
        };
        inputMethod.enable = lib.mkEnableOption "japanese input methods" // {
          default = true;
        };
        environment.enable = lib.mkEnableOption "japanese environment variables" // {
          default = true;
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (lib.mkIf cfg.fonts.enable {
            fonts.packages = [
              pkgs.noto-fonts-cjk-sans
              pkgs.noto-fonts-cjk-serif
            ];
          })

          (lib.mkIf cfg.inputMethod.enable {
            # japanese input managers
            i18n.inputMethod = {
              ibus.engines = [
                pkgs.ibus-engines.mozc-ut
                pkgs.ibus-engines.anthy
              ];
              fcitx5.addons = [
                pkgs.fcitx5-mozc
                pkgs.fcitx5-anthy
              ];
            };
          })

          (lib.mkIf cfg.environment.enable {
            # Configure keymap in X11
            services.xserver.xkb = {
              layout = lib.mkDefault "jp";
              variant = lib.mkDefault "";
            };

            # Configure console keymap
            console.keyMap = lib.mkDefault "jp106";

            # Select internationalisation properties.
            i18n.defaultLocale = lib.mkDefault "ja_JP.UTF-8";
          })

          { i18n.extraLocales = [ "ja_JP.UTF-8/UTF-8" ]; }
        ]
      );
    };
}
