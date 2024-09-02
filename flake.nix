{
  description = "Configurations for some systems";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs?ref=nixos-24.05";
    nixpkgs-pineapplehunter-mozc.url = "github:pineapplehunter/nixpkgs?ref=mozc-updates";
    nixpkgs-pineapplehunter-supprod.url = "github:pineapplehunter/nixpkgs?ref=supprod-from-source";
    nixpkgs-pineapplehunter-mqttx-cli.url = "github:pineapplehunter/nixpkgs?ref=mqttx-cli";
    nixpkgs-pineapplehunter-gitify.url = "github:pineapplehunter/nixpkgs?ref=gitify";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
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
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;
    in
    {
      nixosModules = import ./modules;
      homeModules = (import ./home { inherit self nixpkgs inputs; }).modules;
      homeConfigurations = (import ./home { inherit self nixpkgs inputs; }).configurations;
      overlays = import ./overlay { inherit lib inputs self; };
      nixosConfigurations = import ./machines { inherit lib inputs self; };
    }
    // (inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        legacyPackages = import nixpkgs {
          inherit system;
          overlays = [
            inputs.nixgl.overlays.default
            inputs.nix-xilinx.overlay
            self.overlays.stableOverlay
            self.overlays.fileOverlay
            self.overlays.removeDesktopOverlay
          ];
        };
        callPackage = lib.callPackageWith (legacyPackages // self.packages.${system});
      in
      {
        formatter = legacyPackages.treefmt;
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
