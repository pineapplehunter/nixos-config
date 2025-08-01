{
  description = "A basic shell";

  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      overlays = [ ];
      eachSystem = f: lib.genAttrs systems (system: f (import nixpkgs { inherit system overlays; }));
    in
    {
      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell { packages = with pkgs; [ hello ]; };
      });

      # use nixfmt for all nix files
      formatter = eachSystem (pkgs: pkgs.nixfmt-tree);

      # make all packages accecible with `nix build`
      legacyPackages = eachSystem lib.id;
    };
}
