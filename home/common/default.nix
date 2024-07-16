{ pkgs, lib, config, ... }:
let
  empty-package = pkgs.runCommand "empty-package" { } "mkdir $out";
in
{
  programs = {
    helix = {
      enable = true;
      defaultEditor = true;
      languages = import ./helix-languages.nix {
        inherit lib;
        inherit (pkgs) nixd;
      };
      settings = {
        theme = "github-light";
        editor = {
          line-number = "relative";
          lsp.display-messages = true;
        };
        keys = {
          normal.esc = [ "collapse_selection" ":w" ];
          select.esc = [ "collapse_selection" "normal_mode" ":w" ];
          insert.esc = [ "normal_mode" ":w" ];
        };
      };
      themes = {
        github-light = builtins.fromTOML (builtins.readFile ./helix-github-light.toml);
      };
    };

    zellij = {
      enable = true;
      settings = import ./zellij-config.nix;
    };

    bat = {
      enable = true;
      config = {
        theme = "GitHub";
      };
    };

    starship.enable = true;

    alacritty = {
      enable = true;
      package = empty-package;
      settings = import ./alacritty-config.nix;
    };

    btop = {
      enable = true;
      settings = {
        graph_symbol = "block";
        cpu_single_graph = true;
      };
    };

    zsh = {
      enable = true;
      dotDir = ".config/zsh";
      autosuggestion.enable = true;
    };

    fish.enable = true;

    direnv = {
      enable = true;
      nix-direnv.enable = true;
      config = {
        warn_timeout = "1h";
      };
      silent = true;
    };

    yazi.enable = true;

    gh.enable = true;
  };

  home.packages = with pkgs;[
    nixpkgs-review
    tokei
    npins
    (if pkgs.stdenv.isDarwin then julia-bin else julia)
  ];

  home.file.".julia/config/startup.jl".text = ''
    try
      using OhMyREPL
    catch e
      @warn e
    end
  '';

  home.shellAliases = {
    ls = "${pkgs.eza}/bin/eza --icons --git --time-style '+%y/%m/%d %H:%M'";
    la = "ls -a";
    ll = "ls -lha";
  };

  home.stateVersion = config.home.version.release;
  programs.home-manager.enable = true;
}
