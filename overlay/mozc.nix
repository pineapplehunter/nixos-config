{ inputs, ... }: {
  inherit (inputs.nixpkgs-pineapplehunter.legacyPackages.x86_64-linux.ibus-engines) mozc;
}
