{
  description = "A basic package";

  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { config, ... }:
      {
        flake.overlays.default = final: prev: {
          # Add custom packages
          custom-package = final.callPackage ./package.nix { };
        };

        systems = [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-darwin"
          "x86_64-linux"
        ];

        perSystem =
          { pkgs, system, ... }:
          {
            _module.args.pkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [
                config.flake.overlays.default
                # Add overlays as needed
              ];
            };

            packages.default = pkgs.custom-package;

            # Use nixfmt for all nix files
            formatter = pkgs.nixfmt-tree;

            # Uncomment to build any package with `nix build .#package`
            #legacyPackages = pkgs;
          };
      }
    );
}
