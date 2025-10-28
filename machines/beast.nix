{ inputs, config, ... }:
let
  os-mods = config.flake.nixosModules;
in
{
  flake.nixosConfigurations.beast = inputs.nixpkgs.lib.nixosSystem {
    system = null;
    modules = [
      os-mods.common
      os-mods.personal
      os-mods.beast
    ];
  };
}
