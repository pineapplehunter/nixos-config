{
  description = "Configurations for some systems";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs?ref=nixos-23.11";
    nixpkgs-pineapplehunter.url = "github:pineapplehunter/nixpkgs?ref=mozc-updates";
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
          writeShellScriptBin
          nixos-rebuild
          nix-output-monitor
          nvd
          python3
          mkShellNoCC
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
        devShells.default =
          let
            inherit (nixpkgs.lib) getExe;
            build-script = writeShellScriptBin "build" ''
              ${getExe nix-output-monitor} build ".#nixosConfigurations.$HOST.config.system.build.toplevel" "$@"
              exit $?
            '';
            diff-script = writeShellScriptBin "diff" ''
              set -e
              ${getExe build-script} "$@"
              if [ $(readlink -f ./result) = $(readlink -f /run/current-system) ]; then
                echo All packges up to date!
                exit 1
              fi
              ${getExe nvd} diff /run/current-system ./result
            '';
            switch-script = writeShellScriptBin "switch" ''
              set -e
              ${getExe diff-script} "$@"
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
              git commit -am "$(date -Iminutes)" || true
              sudo ${getExe nixos-rebuild} switch --flake ".#$HOST"
            '';
            boot-script = writeShellScriptBin "boot" ''
              set -e
              ${getExe build-script} "$@"
              sudo echo switching boot
              sudo ${getExe nixos-rebuild} boot --flake ".#$HOST"
            '';
            update-script = writeShellScriptBin "update" ''
              nix flake update
              ${getExe switch-script} "$@"
            '';
          in
          mkShellNoCC {
            packages = [
              build-script
              switch-script
              diff-script
              update-script
              boot-script
            ];
            shellHook = ''
              export HOST=`hostname`
            '';
          };
      }
    ));
}
