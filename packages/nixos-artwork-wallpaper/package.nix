{ stdenv
, fetchFromGitHub
}:

stdenv.mkDerivation {
  pname = "nixos-wallpapers";
  version = "unstable";
  
  src = fetchFromGitHub {
    owner = "nixos";
    repo = "nixos-artwork";
    rev = "35ebbbf01c3119005ed180726c388a01d4d1100c";
    hash = "sha256-t6UXqsBJhKtZEriWdrm19HIbdyvB6V9dR47WHFxENhc=";
  };

  buildPhase = ''
    runHook preBuild
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -pv $out/share/backgrounds/nixos
    cp -v wallpapers/*.png $out/share/backgrounds/nixos
    runHook postInstall
  '';
}
