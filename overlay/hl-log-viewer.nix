{
  flake.overlays.hl-log-viewer = final: prev: {
    # nixpkgs' Rust dependency hooks require system zstd, but hl omits its inputs.
    # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/hl/hl-log-viewer/package.nix
    # The build script also refreshes schema directives over HTTP, causing repeated
    # DNS timeouts in the sandbox. Skip this optional refresh; keep shipped defaults.
    # https://github.com/pamburus/hl/blob/v0.36.3/build.rs
    # Remove when upstream includes pkg-config/zstd and builds without networking.
    hl-log-viewer = prev.hl-log-viewer.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.pkg-config ];
      buildInputs = (old.buildInputs or [ ]) ++ [ final.zstd ];
      postPatch = (old.postPatch or "") + ''
        substituteInPlace build.rs \
          --replace-fail '    update_schema_directives()?;' ""
      '';
    });
  };
}
