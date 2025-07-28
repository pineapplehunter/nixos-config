{
  description = "Configurations for some systems";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    empty.url = "github:pineapplehunter/nix-empty";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-xilinx = {
      url = "gitlab:doronbehar/nix-xilinx?ref=25556ef48ca8042f9432fdacbf2c7d330cb88162";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xremap-flake = {
      url = "github:xremap/nix-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        hyprland.follows = "empty";
      };
    };
    nixos-hardware.url = "github:nixos/nixos-hardware";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    nixgl = {
      url = "github:pineapplehunter/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-search-cli = {
      url = "github:peterldowns/nix-search-cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    howdy-module.url = "github:pineapplehunter/howdy-module";
    proverif-grammar.url = "github:pineapplehunter/tree-sitter-proverif";
    proverif-grammar.flake = false;
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      overlays = [
        inputs.howdy-module.overlays.default
        inputs.nixgl.overlays.default
        inputs.nix-xilinx.overlay
        inputs.agenix.overlays.default
        self.overlays.default
      ];
      eachSystem = f: lib.genAttrs systems (system: f (import nixpkgs { inherit system overlays; }));
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
      formatter = eachSystem (pkgs: pkgs.nixfmt-tree);
      packages = eachSystem (
        pkgs:
        lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          inherit (pkgs)
            stl2pov
            nautilus-thumbnailer-stl
            ;
        }
      );
      devShells = eachSystem (
        pkgs:
        let
          management-tools = pkgs.runCommand "management-tools" { } ''
            mkdir -p $out/bin
            ${pkgs.stdenv.shellDryRun} ${./update.sh}
            ln -s ${./update.sh} $out/bin/os
            ln -s ${./update.sh} $out/bin/home
          '';
        in
        {
          default = pkgs.mkShellNoCC {
            name = "nixos-config";
            packages = [
              management-tools
              pkgs.home-manager
              pkgs.nix-output-monitor
              pkgs.nixos-rebuild
              pkgs.nvd
              pkgs.statix
            ];
            shellHook = ''
              export HOST=`hostname`
            '';
          };
        }
      );
      checks = eachSystem (
        pkgs:
        let
          check-build = drv: pkgs.runCommand "${drv.name}-check" { dummy = "${drv}"; } "touch $out";
          inherit (pkgs.hostPlatform) system;
        in
        {
          user-shogo = check-build self.homeConfigurations."shogo-${system}".activationPackage;
          user-minimal-shogo =
            check-build
              self.homeConfigurations."minimal-shogo-${system}".activationPackage;
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          action = check-build self.nixosConfigurations.action.config.system.build.toplevel;
          beast = check-build self.nixosConfigurations.beast.config.system.build.toplevel;
        }
        // self.packages.${system}
      );
      legacyPackages = eachSystem lib.id;
    };

  nixConfig = {
    extra-substituters = [ "https://attic.s.ihavenojob.work/shogo" ];
    extra-trusted-public-keys = [ "shogo:dzOG75ufKKljdUzTbGDpTuBmup3/K5RDmr28jb0jHCg=" ];
  };
}
