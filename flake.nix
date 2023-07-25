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
      # inputs.utils.follows = "flake-utils";
    };
    nix-xilinx = {
      url = "gitlab:pineapplehunter/nix-xilinx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    curl-http3 = {
      url = "github:pineapplehunter/nix-curl-http3";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
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
            ({ pkgs, ... }: { nixpkgs.overlays = [ (import inputs.rust-overlay) ]; })
            ./os/beast/configuration.nix
          ];
        };
        action = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ({ pkgs, ... }: {
              nixpkgs.overlays = [
                inputs.nix-xilinx.overlay
                inputs.curl-http3.overlays.default
                # (import inputs.rust-overlay)
              ];
            })
            ./os/action/configuration.nix
          ];
        };
      };
    } // (
      let
        overlays = [ (import inputs.rust-overlay) ];
        pkgs = import nixpkgs { system = "x86_64-linux"; inherit overlays; };
      in
      {
        formatter.x86_64-linux = pkgs.nixpkgs-fmt;
        homeConfigurations = {
          "shogo" = inputs.home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [ ./home/home.nix ];
          };
        };
      }
    );

}
