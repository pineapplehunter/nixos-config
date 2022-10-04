{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/22.05";
  };

  outputs = { self, nixpkgs }@inputs:
    let
    in
    {
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;
      nixosConfigurations = {
        mynixhost = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./qemu/configuration.nix
          ];
        };
        beast = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./beast/configuration.nix
          ];
        };
      };
    };
}
