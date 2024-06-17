{
  description = "Configurations for some systems";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs?ref=nixos-23.11";
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
    {
      nixosModules = import ./modules;
      homeConfigurations = import ./home;
      nixosConfigurations = {
        mynixhost = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./machines/qemu/configuration.nix
          ];
        };
        beast = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs self; };
          modules = [
            self.nixosModules.common
            self.nixosModules.personal
            ./machines/beast/configuration.nix
          ];
        };
        action = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs self; };
          modules = [
            inputs.nixos-hardware.nixosModules.dell-xps-13-9310
            inputs.home-manager.nixosModules.home-manager
            self.nixosModules.common
            self.nixosModules.personal
            ./machines/action/configuration.nix
          ];
        };
        micky = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs self; };
          modules = [
            inputs.nixos-hardware.nixosModules.mouse-daiv-z4-i7i01sr-a
            self.nixosModules.common
            self.nixosModules.work
            ./machines/micky/configuration.nix
          ];
        };
      };
    } // (inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        inherit (nixpkgs.legacyPackages.${system})
          nixpkgs-fmt
          callPackage
          python3
          ;
      in
      {
        formatter = nixpkgs-fmt;
        packages = rec {
          nixos-artwork-wallpaper = callPackage ./packages/nixos-artwork-wallpaper/package.nix { };
          stl2pov = callPackage ./packages/stl2pov { };
          nautilus-thumbnailer-stl = callPackage ./packages/nautilus-thumbnailer-stl { inherit stl2pov; };
          nautilus-thumbnailer-3mf = callPackage ./packages/nautilus-thumbnailer-3mf { };
          gcode-thumbnailer = python3.pkgs.callPackage ./packages/gcode-thumbnailer { };
          typst-thumbnailer = callPackage ./packages/typst-thumbnailer { };
        };
        devShells.default = callPackage ./shell.nix { };
      }
    ));
}
