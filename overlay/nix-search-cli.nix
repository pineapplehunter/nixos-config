{ inputs, lib, ... }:
{
  flake.overlays.nix-search-cli = final: prev: {
    # Upstream's VERSION file contains "v0.3\n", which builtins.readFile does not
    # strip, producing a non-standard package version. There is no linked issue or PR.
    # Drop this when upstream normalizes the VERSION value in its Nix package.
    # Last checked: 2026-08-26.
    nix-search-cli =
      inputs.nix-search-cli.packages.${final.stdenv.hostPlatform.system}.default.overrideAttrs
        (old: {
          version = lib.head (lib.match ''[^0-9]*([0-9\.]+).*'' old.version);
          inherit (old) src;
        });
  };
}
