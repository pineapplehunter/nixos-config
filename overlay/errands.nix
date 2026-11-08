{
  flake.overlays.errands = final: prev: {
    # pygobject3's development output propagates GObject introspection development
    # files and glib.dev. Python's wrapper follows those dependencies into PATH,
    # retaining build tools in the runtime closure. Select runtime outputs and
    # include pycairo explicitly because its propagation metadata lives in
    # pygobject3.dev. Existing GTK wrapping supplies the runtime typelibs.
    # Track the dependency declarations in nixpkgs:
    # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/er/errands/package.nix
    # Remove this overlay when upstream avoids development-output propagation.
    errands = prev.errands.overrideAttrs (old: {
      # Meson needs pygobject-3.0.pc during configuration, not at runtime.
      buildInputs = (old.buildInputs or [ ]) ++ [ final.python3Packages.pygobject3 ];
      propagatedBuildInputs = map final.lib.getLib (old.propagatedBuildInputs or [ ]) ++ [
        final.python3Packages.pycairo.out
      ];
    });
  };
}
