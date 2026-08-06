{
  flake.overlays.eza = final: prev: {
    # Add capability support (security.capability xattr display).
    # This can be dropped when the PR is merged and included in the nixpkgs package.
    # https://github.com/eza-community/eza/pull/1624 (still open)
    # Last checked: 2026-08-06.
    eza = prev.eza.overrideAttrs (
      finalAttrs: prevAttrs: {
        version = "0-custom";
        src = final.fetchFromGitHub {
          owner = "pineapplehunter";
          repo = "eza";
          rev = "a5b4beaf75ca2707cd5bfd0daa52a40819d956e2";
          hash = "sha256-xygdTXbWB8rmurZR6r+peJOvaGlzgx9tgFwCWwXH7DU=";
        };
        cargoDeps = final.rustPlatform.fetchCargoVendor {
          inherit (finalAttrs) src pname version;
          hash = "sha256-RBHeP73ivtbEFl0Q1tXdSLmkteiaaYOiNSD6M+4ZUdA=";
        };
        doInstallCheck = false;
      }
    );
  };
}
