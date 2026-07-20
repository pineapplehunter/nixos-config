{ ... }:
{
  flake.overlays.eza = final: prev: {
    # Add capability support (security.capability xattr display).
    # https://github.com/eza-community/eza/pull/1624 (still open)
    eza = prev.eza.overrideAttrs (
      finalAttrs: prevAttrs: {
        version = "0-custom";
        src = final.fetchFromGitHub {
          owner = "pineapplehunter";
          repo = "eza";
          rev = "39ae9d32d8936e539c2f4ca0042fc31fcf0068a1";
          hash = "sha256-OEgql1Wj79EkoGZ/ZgmFVwMmCgLIhukqehCs/Gg7dLA=";
        };
        cargoDeps = final.rustPlatform.fetchCargoVendor {
          inherit (finalAttrs) src pname version;
          hash = "sha256-J6Qu8FFlp3PMTm0M/XT4TqQPaqH57TLBPhQE1Y5hdjg=";
        };
        doInstallCheck = false;
      }
    );
  };
}
