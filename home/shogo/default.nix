{ pkgs, ... }:

{
  home.packages = [ ];

  programs.git = {
    userName = "Shogo Takata";
    userEmail = "peshogo@gmail.com";
  };
}
