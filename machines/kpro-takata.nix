{ inputs, config, ... }:
{
  flake.nixosConfigurations.kpro-takata = inputs.nixpkgs.lib.nixosSystem {
    system = null;
    modules = [ config.flake.nixosModules.kpro-takata ];
  };
}
