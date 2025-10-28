{ inputs, config, ... }:
let
  os-mods = config.flake.nixosModules;
in
{
  flake.nixosConfigurations.kpro-takata = inputs.nixpkgs.lib.nixosSystem {
    system = null;
    modules = [
      inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x1-13th-gen
      os-mods.common
      os-mods.kpro
      os-mods.kpro-takata
    ];
  };
}
