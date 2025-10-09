{ config, ... }:
let
  flake-config = config;
in
{
  flake.homeModules.nixos-common =
    { lib, ... }:
    {
      imports = [ flake-config.flake.homeModules.common ];
      pineapplehunter.isNixos = lib.mkDefault true;
    };
}
