{ pkgs, ... }:

{
  home.packages = builtins.attrValues {
    inherit (pkgs)
      mqttx-cli
      buf
      ;
  };
}
