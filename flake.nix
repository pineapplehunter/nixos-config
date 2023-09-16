{
  description = "Configurations for some systems";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    nixpkgs-gnome.url = "nixpkgs/gnome";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      # inputs.utils.follows = "flake-utils";
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
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-artwork = {
      url = "github:NixOS/nixos-artwork";
      flake = false;
    };
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = { self, nixpkgs, devenv, ... }@inputs:
    {
      nixosConfigurations = {
        mynixhost = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            # {pkgs, ...}: {nixpkgs.overlays = [(import rust-overlay)];}
            ./os/qemu/configuration.nix
          ];
        };
        beast = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ({ pkgs, ... }: { nixpkgs.overlays = [ (import inputs.rust-overlay) ]; })
            ./os/beast/configuration.nix
          ];
        };
        action = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ({ pkgs, ... }: {
              nixpkgs.overlays = [
                inputs.nix-xilinx.overlay
                inputs.curl-http3.overlay
                (import inputs.rust-overlay)
              ];
            })
            ({ pkgs, ... }: {
              nixpkgs.overlays = [
                (final: super: {
                  devenv = devenv.packages.x86_64-linux.devenv;
                  julia = final.symlinkJoin {
                    name = "julia";
                    paths = [ super.julia ];
                    buildInputs = [ final.makeWrapper ];
                    postBuild = ''
                      wrapProgram $out/bin/julia \
                        --set-default PYTHON "${final.python3.withPackages (ps: with ps;[sympy numpy])}/bin/python3"
                    '';
                  };
                  nixos-artwork-wallpaper = final.stdenv.mkDerivation rec {
                    pname = "nixos-wallpapers";
                    version = "1.0.0";
                    src = inputs.nixos-artwork;
                    unpackPhase = "true";
                    buildPhase = "true";
                    installPhase = ''
                      mkdir -pv $out/share/backgrounds/nixos
                      realpath ${src}
                      cp -v ${src}/wallpapers/*.png $out/share/backgrounds/nixos
                    '';
                  };
                  # gnome = inputs.nixpkgs-gnome.legacyPackages.x86_64-linux.gnome;
                })
              ];
            })
            ./os/action/configuration.nix
          ];
        };
      };
    } // (
      let
        overlays = [ (import inputs.rust-overlay) ];
        pkgs = import nixpkgs { system = "x86_64-linux"; inherit overlays; };
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
          {
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
                    yes_or_no "do you want to commit and update?" && git add . && git commit -m "$(date -Iminutes)" && nix run ".#switch"
                  '';
                in
                "${cmd}/bin/nixos-update-script";
            };
          };
      }
    );
}
