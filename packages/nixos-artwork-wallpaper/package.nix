{ stdenv, fetchFromGitHub }:

stdenv.mkDerivation {
  pname = "nixos-wallpapers";
  version = "bootloader-18.09-pre-unstable-2024-05-27";

  src = fetchFromGitHub {
    owner = "nixos";
    repo = "nixos-artwork";
    rev = "53ea652ec7d8af5d21fd2b79b6c49cb39078ddfb";
    hash = "sha256-Zam3vXUBcF09GhaL0eehlTvmhx++qXBO7UhuBySPX84=";
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
