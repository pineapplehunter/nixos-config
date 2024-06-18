{ config, pkgs, lib, ... }:

{
  programs = {
    helix = {
      enable = true;
      defaultEditor = true;
      languages = import ./helix-languages.nix {
        inherit lib;
        inherit (pkgs) nixd;
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
  };

  services.syncthing.enable = true;

  home.packages = with pkgs;[
    julia
    nixpkgs-review
    tokei
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
