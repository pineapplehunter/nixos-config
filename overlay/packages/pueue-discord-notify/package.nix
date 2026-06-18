{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "pueue-discord-notify";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "pineapplehunter";
    repo = "pueue-discord-notify";
    rev = "c3ee4dc01c0a01336aac35c6de96ef660353cfcb";
    hash = "sha256-ZN6RwFwE+tOrU+D77dP0V4koA4tmhy6SHsBGhztuiho=";
  };

  vendorHash = null;

  ldflags = [
    "-s"
    "-w"
  ];

  doCheck = true;

  checkPhase = ''
    runHook preCheck
    go test -v ./...
    runHook postCheck
  '';

  meta = {
    description = "Simple Discord webhook notifier for pueue task completion";
    homepage = "https://github.com/takata/pueue-discord-notify";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "pueue-discord-notify";
  };
}
