{ pkgs, ... }:

{
  home.packages = [
    pkgs.awscli2
    pkgs.buf
    pkgs.mosquitto
    pkgs.mqttx-cli
    pkgs.poetry
    pkgs.uv
  ];

  programs.git = {
    userName = "Shogo Takata";
    userEmail = "shogo.takata@riken.jp";
  };
}
