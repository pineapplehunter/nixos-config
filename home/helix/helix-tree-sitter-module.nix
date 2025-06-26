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
      types.submodule {
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
            type = types.listOf (types.attrsOf types.anything);
          };
        };
      }
    );
  };

  config = {
    xdg.configFile = lib.mkMerge (
      map (
        { name, source, ... }:
        {
          "helix/runtime/queries/${name}".source = pkgs.runCommand "${name}-query" { } ''
            ln -s ${source}/queries $out
          '';
        }
      ) cfg
    );
    programs.helix.languages.grammar = map (
      { name, source, ... }:
      {
        inherit name;
        source.path = source;
      }
    ) cfg;
    programs.helix.languages.language = map (
      { name, ... }@c:
      {
        scope = "source.${name}";
        injection-regex = name;
      }
      // (builtins.removeAttrs c [ "source" ])
    ) cfg;
  };
}
