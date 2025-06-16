{
  description = "A basic shell";

  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  inputs.systems.url = "github:nix-systems/default";

  outputs =
    { nixpkgs, systems, ... }:
    let
      inherit (nixpkgs) lib;
      eachSystem = f: lib.genAttrs (import systems) (system: f (import nixpkgs { inherit system; }));
    in
    {
      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.hello
          ];
        };
      });

      formatter = eachSystem (p: p.nixfmt-tree);

      legacyPackages = eachSystem lib.id;
    };
}
