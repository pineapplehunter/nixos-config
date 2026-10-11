{
  flake.overlays.vtk =
    final: prev:
    let
      # Backport https://github.com/NixOS/nixpkgs/pull/572295.
      # The pinned input renames PEGTL on 9.5 instead of 9.6, mismatching the
      # VTK_MODULE_USE_EXTERNAL flag and causing "PEGTL external dependency" errors.
      # Only 9.6 needs the rename to avoid a target collision with OpenUSD.
      # Remove once the pinned nixpkgs input includes that PR's fix.
      fixPegtl =
        package:
        package.overrideAttrs (oldAttrs: {
          postPatch = prev.lib.optionalString (prev.lib.versionAtLeast oldAttrs.version "9.6") ''
            substituteInPlace ThirdParty/pegtl/vtk.module Common/DataModel/vtk.module IO/MotionFX/vtk.module \
              --replace-fail \
                "VTK::pegtl" \
                "VTK::vtkpegtl"
            substituteInPlace ThirdParty/pegtl/vtkpegtl/CMakeLists.txt \
              --replace-fail \
                "target_compile_features(pegtl" \
                "target_compile_features(vtkpegtl"
          '';
        });
    in
    {
      vtk_9_5 = fixPegtl prev.vtk_9_5;
      vtk_9_6 = fixPegtl prev.vtk_9_6;
    };
}
