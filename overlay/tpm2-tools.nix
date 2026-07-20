{ ... }:
{
  flake.overlays.tpm2-tools = final: prev: {
    # Add Nuvoton TPM certificate support to tpm2-tss.
    # Upstream added Nuvoton certs in tpm2-tss 4.1.4+; pinned nixpkgs
    # is at 4.1.3 so this overlay is still needed.
    tpm2-tools = prev.tpm2-tools.override {
      tpm2-tss = final.tpm2-tss.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          (final.fetchpatch {
            name = "add-nuvoton-certs.patch";
            url = "https://github.com/pineapplehunter/tpm2-tss/commit/6a9adcac623ffcff6bb08fb2c06fa7a6390546f4.patch";
            hash = "sha256-NSJ+NTOK3EJMWe1pf6Tsm26th34VczTD56xldWll1Aw=";
          })
        ];
      });
    };
  };
}
