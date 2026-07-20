{ ... }:
{
  flake.overlays.vtk = final: prev: {
    # Fix build with gdal-3.13: const-correctness conversion error with GCC 15.
    #
    # Upstream fix: this patch has been merged into nixpkgs master via
    # PR #537721 (2026-07-19). Once the nixpkgs input pin is updated past
    # that point, this entire file can be removed.
    vtk = prev.vtk.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        (final.fetchpatch {
          name = "fix-gdal-3.13-const-conversion.patch";
          url = "https://github.com/Kitware/VTK/commit/2395603fdddc40c29efc64c632ae98225ca2a58e.patch";
          hash = "sha256-Gcnt1JXWPkhfNLhtk9SXYqx/0cLkjO4xiRfR8YiaY8I=";
        })
      ];
    });
  };
}
