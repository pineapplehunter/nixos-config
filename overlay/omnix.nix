{
  flake.overlays.omnix = final: prev: {
    # onig_sys uses system oniguruma with the current nixpkgs Rust hooks.
    # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/om/omnix/package.nix
    # Remove when upstream adds oniguruma to the package's build inputs.
    omnix = prev.omnix.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [ final.oniguruma ];
    });
  };
}
