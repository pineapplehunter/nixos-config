{ inputs, ... }:
{
  flake.overlays.niks3 = final: prev: {
    # Use the fork's progress branch so the CLI displays parallel upload progress bars.
    # The fork packages each executable separately, so join them to preserve the three
    # binaries provided by nixpkgs' niks3 package.
    # Drop this override once the progress UI is available in the upstream niks3 package.
    # Fork branch: https://github.com/pineapplehunter/niks3/tree/progress
    # Upstream: https://github.com/Mic92/niks3
    niks3 =
      let
        packages = inputs.niks3.packages.${final.stdenv.hostPlatform.system};
      in
      final.symlinkJoin {
        name = "niks3-${packages.niks3.version}";
        paths = [
          packages.niks3
          packages.niks3-hook
          packages.niks3-server
        ];
        inherit (packages.niks3) meta;
      };
  };
}
