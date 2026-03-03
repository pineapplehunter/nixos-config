{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule (finalAttrs: {
  pname = "helix-assist";
  version = "1.0.10";

  src = fetchFromGitHub {
    owner = "leona";
    repo = "helix-assist";
    tag = "v${finalAttrs.version}";
    hash = "sha256-XYbxEGATUiBLJamwrwmAR1UbyTg6A1QcmJyIxagl3g0=";
  };

  vendorHash = null;

  ldflags = [ "-s" ];

  # remove broken code
  postPatch = ''
    rm -rf cmd/helix-assist-test
    rm -rf tests
  '';

  meta = {
    description = "Code assistant language server for Helix with support for OpenAI/Anthropic";
    homepage = "https://github.com/leona/helix-assist";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pineapplehunter ];
    mainProgram = "helix-assist";
  };
})
