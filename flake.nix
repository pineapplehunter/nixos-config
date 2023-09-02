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
                  #python3 = final.python311;
                  julia = final.writeShellScriptBin "julia" ''
                    PYTHON=${final.python3.withPackages (ps: with ps;[sympy numpy])}/bin/python3 ${super.julia}/bin/julia $@
                  '';
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
                  sudo ${pkgs.nixos-rebuild}/bin/nixos-rebuild ${t} --flake . -v --log-format internal-json |& ${pkgs.nix-output-monitor}/bin/nom --json
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
                
${pkgs.nixos-rebuild}/bin/nixos-rebuild build --flake . -v --log-format internal-json |& ${pkgs.nix-output-monitor}/bin/nom --json
${pkgs.nvd}/bin/nvd diff /run/current-system result
              '';
                in
                "${cmd}/bin/nixos-diff-script";
            };
          };
      }
    );
}
