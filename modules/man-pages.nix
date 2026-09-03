{
  flake.nixosModules.man-pages =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.my.man-pages;
      manPages = pkgs.buildEnv {
        name = "system-man-pages";
        paths = cfg.packages;
        pathsToLink = [ "/share/man" ];
        extraOutputsToInstall = [
          "man"
          "devman"
        ];
        ignoreCollisions = true;
      };
    in
    {
      options.my.man-pages.packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Packages from which to install only manual pages";
      };

      config.environment.systemPackages = lib.mkIf (cfg.packages != [ ]) [ manPages ];
    };
}
