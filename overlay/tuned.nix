{
  flake.overlays.tuned = final: prev: {
    # Python's wrapper follows propagated development outputs into PATH, pulling
    # in GLib headers and GObject introspection build tools. Propagate Python
    # runtime outputs instead, with pycairo explicit because its dependency
    # metadata lives in pygobject3.dev. Keep the existing tool and GTK wrapping.
    # Track the dependency declarations in nixpkgs:
    # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/tu/tuned/package.nix
    # Remove this overlay when upstream avoids development-output propagation.
    tuned = prev.tuned.overrideAttrs (old: {
      propagatedBuildInputs = map final.lib.getLib (old.propagatedBuildInputs or [ ]) ++ [
        final.python3Packages.pycairo.out
      ];
    });
  };
}
