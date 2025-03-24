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
    self.nixosModules.work
    ./action/configuration.nix
  ];
  micky = nixosSystemWrapped [
    inputs.nixos-hardware.nixosModules.mouse-daiv-z4-i7i01sr-a
    self.nixosModules.work
    ./micky/configuration.nix
  ];
}
