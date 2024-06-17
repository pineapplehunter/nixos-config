{ config, pkgs, lib, ... }:

{
  home.username = "shogo";
  home.homeDirectory = "/home/shogo";

  programs = {
    helix = {
      enable = true;
      defaultEditor = true;
      languages = {
        language-server.nixd.command = lib.getExe pkgs.nixd;
        language = [{
          name = "nix";
          auto-format = true;
          language-server = [ "nixd" "nil" ];
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
  };

  home.stateVersion = config.home.version.release;
  programs.home-manager.enable = true;
}
