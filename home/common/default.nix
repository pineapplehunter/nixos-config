{ config, pkgs, lib, ... }:
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

    gnome-shell = {
      enable = true;
      extensions = map (p: { package = p; }) (with pkgs.gnomeExtensions; [
        tailscale-status
        runcat
        caffeine
        appindicator
        just-perfection
        syncthing-indicator
        tiling-assistant
      ]);
    };

    zsh = {
      enable = true;
      dotDir = ".config/zsh";
      autosuggestion.enable = true;
    };

    fish.enable = true;
  };

  services.syncthing.enable = true;

  home.packages = with pkgs;[
    julia
    nixpkgs-review
    tokei
    npins
  ];

  home.file.".julia/config/startup.jl".text = ''
    try
      using OhMyREPL
    catch e
      @warn e
    end
  '';

  home.stateVersion = config.home.version.release;
  programs.home-manager.enable = true;
}
