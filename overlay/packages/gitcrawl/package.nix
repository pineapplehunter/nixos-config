{
  lib,
  stdenv,
  fetchFromGitHub,
  zlib,
  git,
  curl,
  makeWrapper,
}:

stdenv.mkDerivation {
  pname = "gitcrawl";
  version = "1.1.0-unstable-2026-09-01";

  src = fetchFromGitHub {
    owner = "riccivr";
    repo = "gitcrawl";
    rev = "a9e9a68e86bc27f78f340248286a18a053fd75d8";
    hash = "sha256-9pQe4Zt50PzzoVqWq2SAsQlJZpca/okGZ2k66SIp6v4=";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ zlib ];
  makeFlags = [ "PREFIX=$(out)" ];

  postInstall = ''
    wrapProgram "$out/bin/gitcrawl" --prefix PATH : ${
      lib.makeBinPath [
        git
        curl
      ]
    }
  '';

  meta = {
    description = "Archive web pages as diff-friendly Markdown in Git";
    homepage = "https://github.com/riccivr/gitcrawl";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "gitcrawl";
  };
}
