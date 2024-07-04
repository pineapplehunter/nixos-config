{
  description = "Configurations for some systems";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    # nixpkgs-stable.url = "github:nixos/nixpkgs?ref=nixos-24.05";
    nixpkgs-pineapplehunter.url = "github:pineapplehunter/nixpkgs?ref=mozc-updates";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    nix-xilinx = {
      url = "gitlab:doronbehar/nix-xilinx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xremap-flake = {
      url = "github:xremap/nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:pineapplehunter/nixos-hardware";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;
      inherit (lib) mapAttrs nixosSystem;
      nixosSystemWrapped = modules: nixosSystem ({
        system = null;
        specialArgs = { inherit inputs self; };
        modules = [ self.nixosModules.common ] ++ modules;
      });
    in
    {
      nixosModules = import ./modules;
      homeModules = import ./home;
      homeConfigurations = mapAttrs
        (_: mod: inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ self.overlays.default ];
          };
          modules = [ mod ];
        })
        self.homeModules;
      overlays.default = import ./overlay { inherit lib inputs self; };
      nixosConfigurations = {
        mynixhost = nixosSystemWrapped [
          ./machines/qemu/configuration.nix
        ];
        beast = nixosSystemWrapped [
          self.nixosModules.personal
          ./machines/beast/configuration.nix
        ];
        action = nixosSystemWrapped [
          inputs.nixos-hardware.nixosModules.dell-xps-13-9310
          self.nixosModules.personal
          ./machines/action/configuration.nix
        ];
        micky = nixosSystemWrapped [
          inputs.nixos-hardware.nixosModules.mouse-daiv-z4-i7i01sr-a
          self.nixosModules.work
          ./machines/micky/configuration.nix
        ];
      };
    } // (inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
        inherit (pkgs)
          nixpkgs-fmt
          callPackage
          ;
      in
      {
        formatter = nixpkgs-fmt;
        packages = rec {
          nixos-artwork-wallpaper = callPackage ./packages/nixos-artwork-wallpaper/package.nix { };
          stl2pov = callPackage ./packages/stl2pov { };
          nautilus-thumbnailer-stl = callPackage ./packages/nautilus-thumbnailer-stl { inherit stl2pov; };
        };
        devShells.default = callPackage ./shell.nix { };
        legacyPackages = pkgs;
      }
    ));
}
