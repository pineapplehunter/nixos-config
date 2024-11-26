{ pkgs, ... }:

{
  home.packages = builtins.attrValues {
    inherit (pkgs)
      mqttx-cli
      buf
      uv
      ;
  };

  programs.git = {
    userName = "Shogo Takata";
    userEmail = "shogo.takata@riken.jp";
  };
}
