{ pkgs, codexImages }:
let
  piRoot = "${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo";
  broker = pkgs.replaceVars ./pineapplehunter/wrapper/codex_host.mts {
    PI_RUNTIME = "${piRoot}/dist/index.js";
    PI_AI_RETRY = "${piRoot}/node_modules/@earendil-works/pi-ai/dist/utils/retry.js";
  };
  image = pkgs.replaceVars ./pineapplehunter/wrapper/codex_image_host.mts {
    PI_RUNTIME = "${piRoot}/dist";
    IMAGE_PACKAGE = codexImages;
  };
  tsconfig = pkgs.replaceVars ./pineapplehunter/wrapper/codex-tsconfig.json {
    PI_ROOT = piRoot;
  };
in
pkgs.runCommand "pi-codex-host" {
  nativeBuildInputs = [
    pkgs.nodejs
    pkgs.typescript
  ];
} ''
  cp ${broker} codex_host.mts
  cp ${image} codex_image_host.mts
  cp ${./pineapplehunter/wrapper/codex_search.mts} codex_search.mts
  cp ${./pineapplehunter/wrapper/codex_protocol.mts} codex_protocol.mts
  cp ${tsconfig} tsconfig.json
  tsc --project tsconfig.json --pretty false
  for file in ./*.mts; do
    # Check that Node can load this syntax without transforming TypeScript.
    node --check "$file"
  done
  install -Dm644 -t "$out" ./*.mts
''
