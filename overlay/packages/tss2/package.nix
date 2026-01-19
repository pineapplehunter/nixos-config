{
  lib,
  stdenv,
  fetchgit,
  autoreconfHook,
  openssl,
  pkg-config,
}:

stdenv.mkDerivation rec {
  # package name taken from the same package in fedora linux
  pname = "tss2";
  version = "2.4.1";

  src = fetchgit {
    url = "https://git.code.sf.net/p/ibmtpm20tss/tss";
    tag = "v${version}";
    hash = "sha256-P48Zu/JhQopzgQH2CFVvaSMjy2k7EKgkIUqJ3l3nnDg=";
  };

  enableParallelBuilding = true;

  outputs = [
    "out"
    "lib"
    "dev"
    "man"
  ];

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
  ];

  buildInputs = [ openssl ];

  meta = {
    description = "IBM's TPM 2.0 TSS";
    longDescription = ''
      This is a user space TSS for TPM 2.0. It implements the functionality equivalent to (but not API compatible with) the TCG TSS working group's ESAPI, SAPI, and TCTI API's (and perhaps more) but with a hopefully simpler interface.
      It comes with over 110 "TPM tools" samples that can be used for scripted apps, rapid prototyping, education, and debugging.
      It also comes with a web based TPM interface, suitable for a demo to an audience that is unfamiliar with TCG technology. It is also useful for basic TPM management.
    '';
    homepage = "https://sourceforge.net/projects/ibmtpm20tss/";
    license = with lib.licenses; [
      bsd3
      "TCGL" # FIXME: check if this license is usable?
    ];
    maintainers = with lib.maintainers; [ pineapplehunter ];
    platforms = lib.platforms.linux;
  };
}
