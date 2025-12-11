{ inputs, config, ... }:
{
  flake.nixosConfigurations.rpi5 = inputs.nixos-raspberrypi.lib.nixosSystemFull {
    specialArgs = inputs;
    modules = [ config.flake.nixosModules.rpi5 ];
  };
}
