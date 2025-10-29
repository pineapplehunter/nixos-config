{
  description = "A basic shell";

  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { config, ... }:
      {
        # Custom overlays for this shell
        flake.overlays.default = final: prev: { };

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

            devShells.default = pkgs.mkShell {
              packages = with pkgs; [
                hello
              ];
            };

            # Use nixfmt for all nix files
            formatter = pkgs.nixfmt-tree;

            # Uncomment to build any package with `nix build .#package`
            #legacyPackages = pkgs;
          };
      }
    );
}
