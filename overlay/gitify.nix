{ inputs, prev, ... }:
{
  inherit (inputs.nixpkgs-pineapplehunter-gitify.legacyPackages.${prev.system}) gitify;
}
