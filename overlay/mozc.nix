{ inputs, ... }: {
  inherit (inputs.nixpkgs-pineapplehunter-mozc.legacyPackages.x86_64-linux.ibus-engines) mozc mozc-ut;
}
