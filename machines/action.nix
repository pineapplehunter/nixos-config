{ inputs, config, ... }:
let
  os-mods = config.flake.nixosModules;
in
{
  flake.nixosConfigurations.action = inputs.nixpkgs.lib.nixosSystem {
    system = null;
    modules = [
      inputs.nixos-hardware.nixosModules.dell-xps-13-9310
      os-mods.common
      os-mods.personal
      os-mods.action
    ];
  };
}
