{ lib
, self
, inputs
,
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
  mynixhost = nixosSystemWrapped [ ./qemu/configuration.nix ];
  beast = nixosSystemWrapped [
    self.nixosModules.personal
    ./beast/configuration.nix
  ];
  action = nixosSystemWrapped [
    inputs.nixos-hardware.nixosModules.dell-xps-13-9310
    self.nixosModules.personal
    ./action/configuration.nix
  ];
  micky = nixosSystemWrapped [
    inputs.nixos-hardware.nixosModules.mouse-daiv-z4-i7i01sr-a
    self.nixosModules.work
    ./micky/configuration.nix
  ];
}
