{
  flake.overlays.snapper-gui = final: prev: {
    # Propagating GTK and other development outputs makes Python's wrapper walk
    # their build dependencies and retain headers and build tools in its PATH.
    # Keep GTK available to wrapGAppsHook3 for typelibs and schemas, but propagate
    # only Python runtime outputs. pycairo is explicit because pygobject3.out
    # does not carry the dependency metadata stored in pygobject3.dev.
    # Track the dependency declarations in nixpkgs:
    # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/sn/snapper-gui/package.nix
    # pkg_resources was removed from setuptools; use stdlib resource lookup so
    # setuptools is needed only at build time. Remove this overlay when upstream
    # fixes resource lookup and avoids development-output propagation.
    snapper-gui = prev.snapper-gui.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace snappergui/{application,changesWindow,createConfig,createSnapshot,deleteDialog,mainWindow,propertiesDialog,snapshotsView}.py \
          --replace-fail 'import pkg_resources' 'import importlib.resources as resources' \
          --replace-fail 'pkg_resources.resource_filename("snappergui",' 'str(resources.files("snappergui") /'
      '';
      buildInputs = (old.buildInputs or [ ]) ++ [
        final.gtk3
        final.gtksourceview3
      ];
      propagatedBuildInputs = with final.python3Packages; [
        dbus-python.out
        pygobject3.out
        pycairo.out
      ];
      makeWrapperArgs = (old.makeWrapperArgs or [ ]) ++ [
        "--prefix"
        "PATH"
        ":"
        (final.lib.makeBinPath [ final.snapper ])
      ];
    });
  };
}
