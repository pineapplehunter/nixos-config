{ pkgs, ... }:
{
  environment.systemPackages = builtins.attrValues {
    inherit (pkgs)
      webcord
      slack
      super-productivity
      unityhub;
  };
}
