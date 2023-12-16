{
  description = "Configurations for some systems";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
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
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-artwork = {
      url = "github:NixOS/nixos-artwork";
      flake = false;
    };
    xremap-flake = {
      url = "github:xremap/nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = { self, nixpkgs, devenv, ... }@inputs:
    {
      nixosModules = {
        common = import ./modules/common { inherit inputs; };
      };
      nixosConfigurations = {
        mynixhost = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./os/qemu/configuration.nix
          ];
        };
        beast = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            self.nixosModules.common
            ./os/beast/configuration.nix
          ];
        };
        action = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            self.nixosModules.common
            inputs.xremap-flake.nixosModules.default
            inputs.nixos-hardware.nixosModules.dell-xps-13-9310
            ./os/action/configuration.nix
          ];
        };
      };
    } // (
      let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      in
      {
        formatter.x86_64-linux = pkgs.nixpkgs-fmt;
        homeConfigurations = {
          "shogo" = inputs.home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [ ./home/home.nix ];
          };
        };
        apps.x86_64-linux =
          let
            mkApp = t:
              let
                scriptName = "nixos-${t}-script";
                cmd = pkgs.writeShellScriptBin scriptName ''
                  sudo ${pkgs.nixos-rebuild}/bin/nixos-rebuild ${t} --flake . -v --log-format internal-json $@ |& ${pkgs.nix-output-monitor}/bin/nom --json
                '';
              in
              {
                type = "app";
                program = "${cmd}/bin/${scriptName}";
              };
          in
          rec {
            switch = mkApp "switch";
            boot = mkApp "boot";
            build = mkApp "build";
            diff = {
              type = "app";
              program =
                let
                  cmd = pkgs.writeShellScriptBin "nixos-diff-script" ''
                    ${pkgs.nixos-rebuild}/bin/nixos-rebuild build --flake . -v --log-format internal-json $@ |& ${pkgs.nix-output-monitor}/bin/nom --json
                    ${pkgs.nvd}/bin/nvd diff /run/current-system result
                  '';
                in
                "${cmd}/bin/nixos-diff-script";
            };
            update = {
              type = "app";
              program =
                let
                  cmd = pkgs.writeShellScriptBin "nixos-update-script" ''
                    nix flake update
                    ${pkgs.nixos-rebuild}/bin/nixos-rebuild build --flake . -v --log-format internal-json $@ |& ${pkgs.nix-output-monitor}/bin/nom --json
                    if [ $(readlink -f ./result) = $(readlink -f /run/current-system) ]; then
                      echo All packges up to date!
                      exit
                    fi
                    ${pkgs.nvd}/bin/nvd diff /run/current-system result
                    function yes_or_no {
                        while true; do
                            read -p "$* [y/n]: " yn
                            case $yn in
                                [Yy]*) return 0  ;;  
                                [Nn]*) echo "Aborted" ; return  1 ;;
                            esac
                        done
                    }
                    yes_or_no "do you want to commit and update?" && sudo echo starting upgrade && git add . && git commit -m "$(date -Iminutes)" && nix run ".#switch"
                  '';
                in
                "${cmd}/bin/nixos-update-script";
            };
            default = update;
          };
      }
    );
}
