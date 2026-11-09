{ inputs, ... }:
{
  flake.overlays.tpm-passkey = final: _prev: {
    # SQLx's proc macros link system SQLite with the current nixpkgs Rust hooks.
    # Use the input package directly so this also works without its NixOS module.
    # https://github.com/pineapplehunter/tpm-passkey/blob/main/nix/package.nix
    # Remove when the upstream daemon package includes SQLite.
    tpm-passkey-daemon = inputs.tpm-passkey.packages.${final.stdenv.hostPlatform.system}.daemon.overrideAttrs (
      old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ final.sqlite ];
      }
    );
  };
}
