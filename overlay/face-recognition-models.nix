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
          postPatch = (old.postPatch or "") + ''
            substituteInPlace face_recognition_models/__init__.py \
              --replace-fail "from pkg_resources import resource_filename" "from importlib.resources import files" \
              --replace-fail 'resource_filename(__name__, "models/shape_predictor_68_face_landmarks.dat")' 'str(files(__name__).joinpath("models/shape_predictor_68_face_landmarks.dat"))' \
              --replace-fail 'resource_filename(__name__, "models/shape_predictor_5_face_landmarks.dat")' 'str(files(__name__).joinpath("models/shape_predictor_5_face_landmarks.dat"))' \
              --replace-fail 'resource_filename(__name__, "models/dlib_face_recognition_resnet_model_v1.dat")' 'str(files(__name__).joinpath("models/dlib_face_recognition_resnet_model_v1.dat"))' \
              --replace-fail 'resource_filename(__name__, "models/mmod_human_face_detector.dat")' 'str(files(__name__).joinpath("models/mmod_human_face_detector.dat"))'
          '';
        });
      })
    ];
  };
}
