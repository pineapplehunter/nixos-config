{ inputs, ... }:
{
  flake.overlays.niks3 = final: prev: {
    # Use the fork's progress branch so the CLI displays parallel upload progress bars.
    # Drop this override once the progress UI is available in the upstream niks3 package.
    # Fork commit: https://github.com/pineapplehunter/niks3/commit/5017cb7868ffc126257b1dd81a7cb6669b8e27e2
    # Last checked: 2026-08-02.
    niks3 = inputs.niks3.packages.${final.stdenv.hostPlatform.system}.niks3;
  };
}
