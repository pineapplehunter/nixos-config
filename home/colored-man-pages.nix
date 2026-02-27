{
  flake.homeModules.colored-man-pages =
    { lib, config, ... }:
    let
      cfg = config.programs.man.color;
    in
    {
      options.programs.man.color.enable = lib.mkEnableOption "colored man pages";

      config.home.sessionVariables = lib.mkIf cfg.enable {
        MANPAGER = "less --use-color -Dd+r -Du+b";
        MANROFFOPT = "-P -c";
      };
    };
}
