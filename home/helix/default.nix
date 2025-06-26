{ pkgs, ... }:
{
  imports = [ ./helix-tree-sitter-module.nix ];

  config.programs.helix = {
    enable = true;
    defaultEditor = true;
    extraTreesitter = [
      {
        name = "kconfig";
        source = pkgs.fetchFromGitHub {
          owner = "tree-sitter-grammars";
          repo = "tree-sitter-kconfig";
          rev = "486fea71f61ad9f3fd4072a118402e97fe88d26c";
          hash = "sha256-a3uTjtA4KQ8KxEmpva2oHcqp8EwbI5+h9U+qoPSgDd4=";
        };
        comment-token = "#";
        file-types = [
          { glob = "Kconfig"; }
          { glob = "kconfig"; }
        ];
      }
      {
        name = "caddy";
        source = pkgs.fetchFromGitHub {
          owner = "Samonitari";
          repo = "tree-sitter-caddy";
          rev = "65b60437983933d00809c8927e7d8a29ca26dfa3";
          hash = "sha256-IDDz/2kC1Dslgrdv13q9NrCgrVvdzX1kQE6cld4+g2o=";
        };
        comment-token = "#";
        file-types = [
          { glob = "Caddyfile"; }
        ];
      }
      {
        name = "riscvasm";
        source = pkgs.fetchFromGitHub {
          owner = "erihsu";
          repo = "tree-sitter-riscvasm";
          rev = "01e82271a315d57be424392a3e46b2d929649a20";
          hash = "sha256-ZvOs0kAd6fqM+N8mmxBgKRlMrSRAXgy61Cwai6NQglU=";
        };
        comment-token = "#";
        file-types = [
          { glob = "Caddyfile"; }
        ];
      }
      {
        name = "linkerscript";
        source = pkgs.fetchFromGitHub {
          owner = "tree-sitter-grammars";
          repo = "tree-sitter-linkerscript";
          rev = "f99011a3554213b654985a4b0a65b3b032ec4621";
          hash = "sha256-Do8MIcl5DJo00V4wqIbdVC0to+2YYwfy08QWqSLMkQA=";
        };
        comment-token = "#";
        file-types = [
          { glob = "*.ld"; }
          { glob = "*.lds"; }
        ];
      }
      {
        name = "ninja";
        source = pkgs.fetchFromGitHub {
          owner = "alemuller";
          repo = "tree-sitter-ninja";
          rev = "0a95cfdc0745b6ae82f60d3a339b37f19b7b9267";
          hash = "sha256-e/LpQUL3UHHko4QvMeT40LCvPZRT7xTGZ9z1Zaboru4=";
        };
        comment-token = "#";
        file-types = [
          { glob = "*.ninja"; }
        ];
      }
    ];
    languages = import ./helix-languages.nix;
    settings = {
      theme = "github-light";
      editor = {
        lsp = {
          display-messages = true;
          display-inlay-hints = true;
        };
        auto-save = {
          focus-lost = true;
          after-delay.enable = true;
        };
        end-of-line-diagnostics = "hint";
        inline-diagnostics.cursor-line = "warning";
        file-picker.hidden = false;
        bufferline = "multiple";
        insert-final-newline = false;
      };
      keys.normal."C-g" = [
        ":write-all"
        ":new"
        ":insert-output lazygit"
        ":buffer-close!"
        ":redraw"
        ":reload-all"
      ];
    };
    themes = {
      github-light = builtins.fromTOML (builtins.readFile ./helix-github-light.toml);
    };
  };

  config.home.packages = with pkgs; [
    # for editors
    basedpyright
    bash-language-server
    buf
    clang-tools
    marksman
    nixd
    ruff
    taplo
    texlab
    tinymist
    vscode-langservers-extracted
    nodePackages.typescript-language-server
  ];
}
