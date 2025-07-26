{
  description = "A basic package";

  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      overlays = [ self.overlays.default ];
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
        default = pkgs.some-package;
      });

      # use nixfmt for all nix files
      formatter = eachSystem (pkgs: pkgs.nixfmt-tree);

      # make all packages accecible with `nix build`
      legacyPackages = eachSystem lib.id;
    };
}
