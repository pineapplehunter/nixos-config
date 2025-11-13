{
  description = "Configurations for some systems";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    empty.url = "github:pineapplehunter/nix-empty";
    flake-parts.url = "github:hercules-ci/flake-parts";
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
    nixos-hardware.url = "github:pineapplehunter/nixos-hardware";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    nixgl = {
      url = "github:pineapplehunter/nixGL?ref=fix-system";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-search-cli = {
      url = "github:peterldowns/nix-search-cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    howdy-module.url = "github:pineapplehunter/howdy-module";
    rust-overlay.url = "github:oxalica/rust-overlay";
    lanzaboote = {
      url = "github:nix-community/lanzaboote?ref=v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };
  };

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { config, ... }:
      {
        imports = [
          ./home/default.nix
          ./machines/default.nix
          ./modules/default.nix
          ./overlay/default.nix
          ./templates/default.nix
          ./secrets/default.nix
        ];

        systems = [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-darwin"
          "x86_64-linux"
        ];

        perSystem =
          {
            pkgs,
            lib,
            system,
            ...
          }:
          {
            legacyPackages = pkgs;
            formatter = pkgs.nixfmt-tree;
            devShells.default =
              let
                management-tools = pkgs.runCommand "management-tools" { } ''
                  mkdir -p $out/bin
                  ${pkgs.stdenv.shellDryRun} ${./update.sh}
                  ln -s ${./update.sh} $out/bin/os
                  ln -s ${./update.sh} $out/bin/home
                '';
              in
              pkgs.mkShellNoCC {
                name = "nixos-config";
                packages = [
                  management-tools
                  pkgs.home-manager
                  pkgs.nix-output-monitor
                  pkgs.nvd
                  pkgs.statix
                ];
                shellHook = ''
                  export HOST=`hostname`
                '';
              };

            packages.ci =
              let
                check-build = drv: pkgs.runCommand "${drv.name}-check" { dummy = drv; } "touch $out";
              in
              pkgs.runCommand "fast-check" {
                dummy = map check-build (lib.attrValues config.flake.checks.${system}) ++ [
                  (check-build config.flake.devShells.${system}.default)
                ];
              } "touch $out";

            checks = {
              user-shogo = config.flake.homeConfigurations."shogo-${system}".activationPackage;
              user-minimal-shogo = config.flake.homeConfigurations."minimal-shogo-${system}".activationPackage;
            }
            // lib.optionalAttrs (system == "x86_64-linux") {
              action = config.flake.nixosConfigurations.action.config.system.build.toplevel;
              beast = config.flake.nixosConfigurations.beast.config.system.build.toplevel;
              kpro-takata = config.flake.nixosConfigurations.kpro-takata.config.system.build.toplevel;
            }
            // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
              inherit (pkgs)
                stl2pov
                nautilus-thumbnailer-stl
                ;
            };
          };
      }
    );

  nixConfig = {
    extra-substituters = [ "https://attic.s.ihavenojob.work/shogo" ];
    extra-trusted-public-keys = [ "shogo:R9ZWo9iGw8E0X6G24R7XLPH0UeE3VZ/WFi2+D0Kmud4=" ];
  };
}
