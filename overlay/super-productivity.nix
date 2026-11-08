{
  flake.overlays.super-productivity = final: prev: {
    # Bundled dependency CLI shebangs retain build-time Node despite Electron's
    # embedded runtime. Scrub node_modules after the app build, before packaging
    # computes ASAR hashes. Invoke the builder with Node because its own shebang
    # is scrubbed too.
    # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/su/super-productivity/package.nix
    # Remove when upstream stops retaining Node through bundled CLIs.
    super-productivity = prev.super-productivity.overrideAttrs (old: {
      nativeBuildInputs = old.nativeBuildInputs ++ [ final.removeReferencesTo ];
      buildPhase =
        builtins.replaceStrings
          [ "npm exec electron-builder --" ]
          [
            ''
              find node_modules -type f -exec remove-references-to -t ${final.nodejs_24} {} +
              node node_modules/electron-builder/cli.js''
          ]
          old.buildPhase;
      disallowedReferences = (old.disallowedReferences or [ ]) ++ [ final.nodejs_24 ];
    });
  };
}
