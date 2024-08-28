{ inputs, prev, ... }:
{
  mqttx-cli = inputs.nixpkgs-pineapplehunter-mqttx-cli.legacyPackages.${prev.system}.mqttx-cli;
}
