{
  description = "Configurations for some systems";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs?ref=nixos-24.05";
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
    in
    {
      nixosModules = import ./modules;
      homeModules = import ./home;
      homeConfigurations = lib.mapAttrs
        (_: mod: inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          modules = [
            { nixpkgs.overlays = [ self.overlays.default ]; }
            mod
          ];
        })
        self.homeModules;
      overlays.default = import ./overlay { inherit lib inputs self; };
      nixosConfigurations = import ./machines { inherit lib inputs self; };
    } // (inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        legacyPackages = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
        callPackage = lib.callPackageWith (legacyPackages // self.packages.${system});
      in
      {
        formatter = legacyPackages.nixpkgs-fmt;
        packages = {
          nixos-artwork-wallpaper = callPackage ./packages/nixos-artwork-wallpaper/package.nix { };
          stl2pov = callPackage ./packages/stl2pov { };
          nautilus-thumbnailer-stl = callPackage ./packages/nautilus-thumbnailer-stl { };
        };
        devShells.default = callPackage ./shell.nix { };
        inherit legacyPackages;
      }
    ));
}
