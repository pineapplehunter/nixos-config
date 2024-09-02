{ inputs, final, ... }:
{
  mqttx-cli = final.callPackage (
    inputs.nixpkgs-pineapplehunter-mqttx-cli + /pkgs/by-name/mq/mqttx-cli/package.nix
  ) { };
}
