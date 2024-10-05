{
  stdenv,
  fetchFromGitHub,
}:

stdenv.mkDerivation {
  pname = "sample-name";
  version = "9.9.9";
  src = fetchFromGitHub {
    owner = "";
    repo = "";
    rev = "";
    hash = "";
  };
  meta = { };
}
