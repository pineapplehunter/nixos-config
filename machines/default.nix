{
  lib,
  self,
  inputs,
}:
let
  nixosSystemWrapped =
    modules:
    lib.nixosSystem {
      system = null;
      specialArgs = {
        inherit inputs self;
      };
      modules = [ self.nixosModules.common ] ++ modules;
    };
in
{
  beast = nixosSystemWrapped [
    self.nixosModules.personal
    ./beast/configuration.nix
  ];
  action = nixosSystemWrapped [
    inputs.nixos-hardware.nixosModules.dell-xps-13-9310
    self.nixosModules.personal
    self.nixosModules.niri
    ./action/configuration.nix
  ];
  kpro-takata = nixosSystemWrapped [
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x1-13th-gen
    inputs.lanzaboote.nixosModules.lanzaboote
    self.nixosModules.personal
    self.nixosModules.niri
    ./kpro-takata/configuration.nix
  ];
}
