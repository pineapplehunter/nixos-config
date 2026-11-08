{
  flake.overlays.canon-cups-ufr2 = final: prev: {
    # Reduce the driver's runtime closure by removing its unused full-GCC RPATH.
    # nixpkgs disables ELF fixup because RPATH shrinking cannot detect libraries
    # loaded through dlopen. Enable shrinking, then restore only those paths in
    # postFixup; the separate GCC runtime libraries remain available as needed.
    # Background: color-printing and C++ runtime-library fixes in nixpkgs:
    # https://github.com/NixOS/nixpkgs/commit/3ce3d5b24093459af9ed1e9257e550fef224b6b9
    # https://github.com/NixOS/nixpkgs/commit/80314e12ffd9554cbd6261ca9bfad7a290452b6f
    # Track pkgs/by-name/ca/canon-cups-ufr2/package.nix in nixpkgs. Remove this
    # overlay when that package excludes full GCC while retaining dlopen support.
    # Internal Canon libraries use existing RPATHs for linked dependencies and
    # the cnrsdrvufr2 wrapper's LD_LIBRARY_PATH for dynamically loaded libraries.
    canon-cups-ufr2 = prev.canon-cups-ufr2.overrideAttrs (old: {
      dontPatchELF = false;
      postFixup = (old.postFixup or "") + ''
        # These libraries are opened by name, not declared in DT_NEEDED.
        patchelf --add-rpath "${final.lib.makeLibraryPath [ final.libjpeg ]}" \
          "$out/lib/libcanonufr2r.so.1.0.0"
        patchelf --add-rpath "${final.lib.makeLibraryPath [ final.libgcrypt ]}" \
          "$out/bin/cnpkmoduleufr2r"
        patchelf --add-rpath "${final.lib.makeLibraryPath [ final.jbigkit ]}" \
          "$out/bin/cnjbigufr2"
      '';
    });
  };
}
