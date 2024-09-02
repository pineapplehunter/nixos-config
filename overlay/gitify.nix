{ inputs, final, ... }:
{
  gitify = final.callPackage (inputs.nixpkgs-pineapplehunter-gitify + /pkgs/by-name/gi/gitify/package.nix) {};
}
