{ pkgs, lib, ... }:
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
        comment-tokens = [ "#" ];
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
        comment-tokens = [ "#" ];
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
        comment-tokens = [ "#" ];
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
        comment-tokens = [ "#" ];
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
        comment-tokens = [ "#" ];
        file-types = [
          { glob = "*.ninja"; }
        ];
      }
      {
        name = "tamarin";
        source = pkgs.fetchFromGitHub {
          owner = "aeyno";
          repo = "tree-sitter-tamarin";
          rev = "07e2f32c1e9f68e8b813b8eca924a61f2c4b94d8";
          hash = "sha256-J2LoV0mu1PDMrwGoK671naWpT50dv3muR/WJ3MyRQOI=";
        };
        comment-tokens = [ "//" ];
        file-types = [
          { glob = "*.spthy"; }
        ];
      }
      {
        name = "proverif";
        source = pkgs.fetchFromGitHub {
          owner = "pqcfox";
          repo = "tree-sitter-proverif";
          rev = "bd9222e7bab33a6b22b4ecfa8e0a618683487935";
          hash = "sha256-YFB1eXVjTzSMSzKyaLsiQZJykfMvv6JOgi71zs4w9vU=";
        };
        block-comment-tokens = [
          {
            start = "(*";
            end = "*)";
          }
        ];
        file-types = [
          { glob = "*.pv"; }
        ];
      }
    ];
    languages = lib.importTOML ./helix-languages.toml;
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
      github-light = lib.importTOML ./helix-github-light.toml;
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
