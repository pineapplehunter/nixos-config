{
  flake.overlays.super-productivity = final: prev: {
    # Backport 19.3.1 and its build fixes while the pinned nixpkgs has 19.1.0.
    # Track the contents of https://github.com/NixOS/nixpkgs/pull/579099,
    # including source/dependency hashes, Electron version, and build changes.
    # Remove once the pinned nixpkgs includes the update and build fixes.
    super-productivity =
      (prev.super-productivity.override {
        electron_43 = final.electron_44;
      }).overrideAttrs
        (old: {
          version = "19.3.1";
          src = final.fetchFromGitHub {
            owner = "super-productivity";
            repo = "super-productivity";
            tag = "v19.3.1";
            hash = "sha256-RlDpD+dfJiMjXlbVq1hW16eyt+S/IFGiJvoce6ZWAEM=";
          };
          npmDeps = old.npmDeps.overrideAttrs {
            outputHash = "sha256-q0mj8EJ2RE/i6u5FjT/Fm+7GyMLnF2FqIxsfKQO2SNU=";
          };
          nativeBuildInputs = [ final.gitMinimal ] ++ old.nativeBuildInputs;
          env = old.env // {
            # Use JavaScript Sass instead of the bundled Dart executable.
            NG_BUILD_SASS_EMBEDDED = "false";
          };
        });
  };
}
