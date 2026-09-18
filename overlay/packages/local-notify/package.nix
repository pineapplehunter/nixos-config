{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "local-notify";
  version = "1.0.0";

  src = ./.;
  vendorHash = null;
  subPackages = [
    "cmd/local-notify"
    "cmd/local-notifyd"
  ];

  ldflags = [
    "-s"
    "-w"
  ];

  doCheck = false;

  meta = {
    description = "Local Unix-socket to Discord notification bridge";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "local-notify";
  };
}
