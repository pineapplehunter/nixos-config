{
  description = "Configurations for some systems";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-xilinx = {
      url = "gitlab:doronbehar/nix-xilinx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    curl-http3 = {
      url = "github:pineapplehunter/nix-curl-http3";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
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
      nixosModules = {
        common = import ./modules/common;
        helix = import ./modules/helix;
        shell-config = import ./modules/shell-config;
        japanese = import ./modules/japanese;
        personal = import ./modules/personal;
        work = import ./modules/work;
      };
      nixosConfigurations = {
        mynixhost = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./machines/qemu/configuration.nix ];
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
    } // (
      let
        inherit (nixpkgs) lib;
        inherit (nixpkgs.legacyPackages.x86_64-linux)
          nixpkgs-fmt callPackage writeShellScript nixos-rebuild nix-output-monitor nvd pkgs;
      in
      {
        formatter.x86_64-linux = nixpkgs-fmt;
        homeConfigurations = {
          "shogo" = inputs.home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [ ./home/home.nix ];
          };
        };
        packages.x86_64-linux = {
          nixos-artwork-wallpaper = callPackage ./packages/nixos-artwork-wallpaper/package.nix { };
        };
        apps.x86_64-linux =
          let
            mkScriptApp = name: script: {
              type = "app";
              program = "${writeShellScript name script}";
            };
          in
          rec {
            switch = mkScriptApp "switch" ''
              set +e
              export HOST=''${HOST:-$(hostname)}
              ${lib.getExe nix-output-monitor} build ".#nixosConfigurations.$HOST.config.system.build.toplevel" "$@"
              sudo echo switching
              sudo ${lib.getExe nixos-rebuild} switch --flake .
            '';
            boot = mkScriptApp "boot" ''
              set +e
              export HOST=''${HOST:-$(hostname)}
              ${lib.getExe nix-output-monitor} build ".#nixosConfigurations.$HOST.config.system.build.toplevel" "$@"
              sudo echo switching boot
              sudo ${lib.getExe nixos-rebuild} boot --flake .
            '';
            build = mkScriptApp "build" ''
              export HOST=''${HOST:-$(hostname)}
              ${lib.getExe nix-output-monitor} build ".#nixosConfigurations.$HOST.config.system.build.toplevel" "$@"
            '';
            diff = mkScriptApp "diff" ''
              set +e
              export HOST=''${HOST:-$(hostname)}
              ${lib.getExe nix-output-monitor} build ".#nixosConfigurations.$HOST.config.system.build.toplevel" "$@"
              ${lib.getExe nvd} diff /run/current-system result
            '';
            update = mkScriptApp "update-system" ''
              set -e
              export HOST=''${HOST:-$(hostname)}
              ${lib.getExe nix-output-monitor} build ".#nixosConfigurations.$HOST.config.system.build.toplevel" "$@"
              if [ $(readlink -f ./result) = $(readlink -f /run/current-system) ]; then
                echo All packges up to date!
                exit
              fi
              ${lib.getExe nvd} diff /run/current-system ./result
              function yes_or_no {
                  while true; do
                      read -p "$* [y/n]: " yn
                      case $yn in
                          [Yy]*) return 0  ;;
                          [Nn]*) echo "Aborted" ; return 1 ;;
                      esac
                  done
              }
              yes_or_no "do you want to commit and update?"
              sudo echo starting upgrade
              git commit -am "$(date -Iminutes)"
              sudo ${lib.getExe nixos-rebuild} switch --flake ".#$HOST"
            '';
            default = update;
          };
      }
    );
}
