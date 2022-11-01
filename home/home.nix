{ config, lib, pkgs, ... }:
let
  username = "shogo";
in
{
  home.homeDirectory = "/home/${username}";
  home.username = "${username}";
  nixpkgs.config = { allowUnfree = true; };
  home.stateVersion = "22.05";
  programs.home-manager.enable = true;
  home.packages = with pkgs; [
    # cargo rustc
  ];
}
