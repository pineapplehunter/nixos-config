{ inputs, final, ... }:
{
  super-productivity = final.callPackage (
    inputs.nixpkgs-pineapplehunter-supprod + /pkgs/by-name/su/super-productivity/package.nix
  ) { };
}
