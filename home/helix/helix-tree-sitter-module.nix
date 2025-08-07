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
          comment-tokens = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          block-comment-tokens = mkOption {
            type = types.listOf (
              types.submodule {
                options = {
                  start = mkOption { type = types.str; };
                  end = mkOption { type = types.str; };
                };
              }
            );
            default = [ ];
          };
          file-types = mkOption {
            type = types.listOf types.anything;
            default = [ ];
          };
        };
      }
    );
  };

  config =
    let
      cfg-with-parser = map (
        { name, source, ... }@inputs:
        {
          parser = pkgs.tree-sitter.buildGrammar {
            src = source;
            version = "0-unknown";
            language = name;
          };
        }
        // inputs
      ) cfg;
    in
    {
      xdg.configFile = lib.mkMerge (
        map (
          { name, parser, ... }:
          {
            "helix/runtime/queries/${name}".source = "${parser}/queries";
            "helix/runtime/grammars/${name}.so".source = "${parser}/parser";
          }
        ) cfg-with-parser
      );
      programs.helix.languages.grammar = map (
        { name, source, ... }:
        {
          inherit name;
          source.git = source.url;
        }
      ) cfg;
      programs.helix.languages.language = map (
        { name, ... }@c:
        {
          scope = "source.${name}";
          injection-regex = name;
        }
        // (lib.removeAttrs c [ "source" ])
      ) cfg;
    };
}
