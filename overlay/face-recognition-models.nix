{ ... }:
{
  flake.overlays.face-recognition-models = final: prev: {
    # Still needed as of 2026-07-20:
    # Upstream (ageitgey/face_recognition_models) abandoned since 2017.
    # Still uses deprecated pkg_resources; without this overlay the
    # package is broken on Python 3.14+.
    pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
      (python-final: python-prev: {
        face-recognition-models = python-prev.face-recognition-models.overridePythonAttrs (old: {
          propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [ python-prev.setuptools_80 ];
        });
      })
    ];
  };
}
