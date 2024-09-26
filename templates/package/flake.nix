{
  description = "A basic package";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
    }:
    let
      eachSystem = nixpkgs.lib.genAttrs (import systems);
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      packages = eachSystem (
        system:
        let
          pkgs = (pkgsFor system) // (builtins.removeAttrs self.packages.${system} [ "default" ]);
          callPackage = nixpkgs.lib.callPackageWith pkgs;
        in
        {
          default = callPackage ./package.nix { };
        }
      );
    };
}
