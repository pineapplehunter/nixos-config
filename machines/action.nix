{ inputs, config, ... }:
{
  flake.nixosConfigurations.action = inputs.nixpkgs.lib.nixosSystem {
    system = null;
    modules = [ config.flake.nixosModules.action ];
  };
}
