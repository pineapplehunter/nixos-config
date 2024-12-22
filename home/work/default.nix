{ pkgs, ... }:

{
  home.packages = builtins.attrValues {
    inherit (pkgs)
      mqttx-cli
      buf
      uv
      mosquitto
      ;
  };

  programs.git = {
    userName = "Shogo Takata";
    userEmail = "shogo.takata@riken.jp";
  };
}
