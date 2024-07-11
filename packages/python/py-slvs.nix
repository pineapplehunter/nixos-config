{
  buildPythonPackage,
  fetchFromGitHub,
  cmake,
  ninja,
  scikit-build,
  swig,
}:
buildPythonPackage rec {
  pname = "py-slvs";
  version = "1.0.6";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "realthunder";
    repo = "slvs_py";
    rev = "v${version}";
    hash = "sha256-/eYfzvU9zBtWyEkdi8Hux+rwo/MZ8vY/fJ3EdEdl7iY=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    cmake
    ninja
    swig
    scikit-build
  ];
  dontUseCmakeConfigure = true;

  doCheck = false;

  # propagatedBuildInputs = [  ];
}
