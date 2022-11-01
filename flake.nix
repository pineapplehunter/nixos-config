{
  description = "Configurations for some systems";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, home-manager }:
    {
      nixosConfigurations = {
        mynixhost = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            # {pkgs, ...}: {nixpkgs.overlays = [(import rust-overlay)];}
            ./os/qemu/configuration.nix
          ];
        };
        beast = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ({pkgs, ...}: {nixpkgs.overlays = [ (import rust-overlay)];})
            ./beast/configuration.nix
          ];
        };
      };
    } // {
      homeConfigurations =
        let
          overlays = [ (import rust-overlay) ];
          pkgs = import nixpkgs { system = "x86_64-linux"; inherit overlays; };
        in
        {
          "shogo" = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [ ./home/home.nix ];
          };
        };
    } //
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ ];
        pkgs = import nixpkgs { inherit system overlays; };
      in
      {
        formatter = pkgs.nixpkgs-fmt;
      });

}
