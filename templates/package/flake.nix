{
  description = "A basic package";

  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

  outputs =
    { nixpkgs, config, ... }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      overlays = [ config.flake.overlays.default ];
      eachSystem = f: lib.genAttrs systems (system: f (import nixpkgs { inherit system overlays; }));
    in
    {
      # add packages from `pkgs` directory
      overlays.default =
        final: prev:
        lib.packagesFromDirectoryRecursive {
          inherit (final) callPackage;
          directory = ./pkgs;
        };

      packages = eachSystem (pkgs: {
        # change name to the added package
        default = pkgs.custom-package;
      });

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell { packages = with pkgs; [ hello ]; };
      });

      # use nixfmt for all nix files
      formatter = eachSystem (pkgs: pkgs.nixfmt-tree);

      # make all packages accecible with `nix build`
      legacyPackages = eachSystem lib.id;
    };
}
