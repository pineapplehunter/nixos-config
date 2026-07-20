{ inputs, lib, ... }:
{
  flake.overlays.nix-search-cli = final: prev: {
    # Fix issue: non-standard version representation.
    # Upstream VERSION file contains "v0.3\n" which builtins.readFile
    # does not strip, producing an invalid version string.
    nix-search-cli =
      inputs.nix-search-cli.packages.${final.stdenv.hostPlatform.system}.default.overrideAttrs
        (old: {
          version = lib.head (lib.match ''[^0-9]*([0-9\.]+).*'' old.version);
          inherit (old) src;
        });
  };
}
