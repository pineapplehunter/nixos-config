{
  description = "Configurations for some systems";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs?ref=nixos-24.05";
    nixpkgs-pineapplehunter-supprod.url = "github:pineapplehunter/nixpkgs?ref=supprod-from-source";
    nixpkgs-pineapplehunter-mqttx-cli.url = "github:pineapplehunter/nixpkgs?ref=mqttx-cli";
    nixpkgs-pineapplehunter-gitify.url = "github:pineapplehunter/nixpkgs?ref=gitify";
    npm-lockfile-fix = {
      url = "github:pineapplehunter/npm-lockfile-fix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-xilinx = {
      url = "gitlab:doronbehar/nix-xilinx?ref=25556ef48ca8042f9432fdacbf2c7d330cb88162";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xremap-flake = {
      url = "github:xremap/nix-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        treefmt-nix.follows = "treefmt-nix";
        home-manager.follows = "home-manager";
      };
    };
    nixos-hardware.url = "github:pineapplehunter/nixos-hardware";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-search-cli = {
      url = "github:peterldowns/nix-search-cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;
      eachSystem = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      pkgsForSystem =
        system:
        import nixpkgs {
          inherit system;
          overlays = [
            inputs.nixgl.overlays.default
            inputs.nix-xilinx.overlay
            self.overlays.default
          ];
        };
    in
    {
      nixosModules = import ./modules;
      homeModules = (import ./home { inherit self nixpkgs inputs; }).modules;
      homeConfigurations = (import ./home { inherit self nixpkgs inputs; }).configurations;
      overlays = import ./overlay { inherit lib inputs self; };
      nixosConfigurations = import ./machines { inherit lib inputs self; };
      templates = import ./templates;
    }
    // {
      formatter = eachSystem (
        system:
        (inputs.treefmt-nix.lib.evalModule (pkgsForSystem system) {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }).config.build.wrapper

      );
      packages = eachSystem (
        system:
        let
          pkgs = pkgsForSystem system;
          callPackage = lib.callPackageWith (pkgs // self.packages.${system});
        in
        {
          stl2pov = callPackage ./packages/stl2pov { };
          nautilus-thumbnailer-stl = callPackage ./packages/nautilus-thumbnailer-stl { };
        }
      );
      devShells = eachSystem (system: {
        default = (pkgsForSystem system).callPackage ./shell.nix { };
      });
      legacyPackages = eachSystem pkgsForSystem;
    };
}
