{ pkgs }:
let
  upstream = pkgs.fetchurl {
    url = "https://registry.npmjs.org/pi-codex-image-gen/-/pi-codex-image-gen-0.3.2.tgz";
    hash = "sha256-kPbwZUPnyOMr/3Ou0miCe8R08GoBjrmEDK1iQYeZ/L8=";
  };
  photon = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@silvia-odwyer/photon-node/-/photon-node-0.3.4.tgz";
    hash = "sha256-WiMBXBzSw448SS3ZaSmYUke5L1LS/w+5SNKe3KUrxQo=";
  };
in
pkgs.runCommand "pi-codex-images-0.3.2" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
  mkdir -p "$out/node_modules/@silvia-odwyer/photon-node"
  tar -xzf ${upstream} --strip-components=1 -C "$out"
  tar -xzf ${photon} --strip-components=1 -C "$out/node_modules/@silvia-odwyer/photon-node"
  cd "$out"
  patch -p1 < ${./pineapplehunter/wrapper/codex-image.patch}
  cp ${./pineapplehunter/wrapper/codex_image_client.ts} src/host-image.ts
  # The host imports only these modules, not the Pi extension or its tools.
  node --input-type=module <<'JS'
  import { readFileSync, writeFileSync } from 'node:fs';
  import { stripTypeScriptTypes } from 'node:module';
  for (const name of ['image-oauth', 'images-request', 'codex-response']) {
    const path = 'src/' + name;
    writeFileSync(path + '.js', stripTypeScriptTypes(readFileSync(path + '.ts', 'utf8'), { mode: 'transform' }));
  }
  JS
''
