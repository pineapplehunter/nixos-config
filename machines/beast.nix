{ inputs, config, ... }:
{
  flake.nixosConfigurations.beast = inputs.nixpkgs.lib.nixosSystem {
    system = null;
    modules = [ config.flake.nixosModules.beast ];
  };
}
