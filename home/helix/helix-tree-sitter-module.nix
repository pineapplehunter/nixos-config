{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.programs.helix.extraTreesitter;
in
{
  options.programs.helix.extraTreesitter = lib.mkOption {
    type = lib.types.listOf (
      types.submodule (
        { ... }:
        {
          options = {
            name = mkOption {
              type = types.str;
            };
            source = mkOption {
              type = types.package;
            };
            comment-token = mkOption {
              type = types.str;
            };
            file-types = mkOption {
              type = types.listOf (
                types.submodule (
                  { ... }:
                  {
                    options.glob = mkOption { type = types.str; };
                  }
                )
              );
            };
          };
        }
      )
    );
  };

  config.xdg.configFile = lib.mkMerge (
    map (
      { name, source, ... }:
      {
        "helix/runtime/queries/${name}".source = pkgs.runCommand "${name}-query" { } ''
          ln -s ${source}/queries $out
        '';
      }
    ) cfg
  );
  config.programs.helix.languages.grammar = (
    map (
      { name, source, ... }:
      {
        name = name;
        source.path = source;
      }
    ) cfg
  );
  config.programs.helix.languages.language = (
    map (
      { name, ... }@c:
      {
        scope = "source.${name}";
        injection-regex = name;
      }
      // (builtins.removeAttrs c [ "source" ])
    ) cfg
  );
}
