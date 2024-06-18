{ config, pkgs, lib, ... }:

{
  programs = {
    helix = {
      enable = true;
      defaultEditor = true;
      languages = {
        language-server.nixd.command = lib.getExe pkgs.nixd;
        language = [{
          name = "nix";
          auto-format = true;
          language-servers = [ "nixd" "nil" ];
        }];
      };
    };

    zellij = {
      enable = true;
      settings = {
        theme = "light";
        themes.light = {
          fg = "#DCD7BA";
          bg = "#1F1F28";
          red = "#C34043";
          green = "#76946A";
          yellow = "#FF9E3B";
          blue = "#0000FF";
          magenta = "#957FB8";
          orange = "#FFA066";
          cyan = "#7FB4CA";
          black = "#16161D";
          white = "#DCD7BA";
        };
      };
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
      settings = {
        colors = {
          primary = {
            background = "#ffffff";
            foreground = "#24292f";
          };
          normal = {
            black = "#24292e";
            red = "#d73a49";
            green = "#28a745";
            yellow = "#dbab09";
            blue = "#0366d6";
            magenta = "#5a32a3";
            cyan = "#0598bc";
            white = "#6a737d";
          };
        };
        bright = {
          black = "#959da5";
          red = "#cb2431";
          green = "#22863a";
          yellow = "#b08800";
          blue = "#005cc5";
          magenta = "#5a32a3";
          cyan = "#3192aa";
          white = "#d1d5da";
        };
        colors.indexed_colors = [
          {
            index = 16;
            color = "#d18616";
          }
          {
            index = 17;
            color = "#cb2431";
          }
        ];
      };
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
