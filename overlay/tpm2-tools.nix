{
  flake.overlays.tpm2-tools = final: prev: {
    # Add Nuvoton TPM root certificates missing from pinned tpm2-tss 4.1.3.
    # Upstream commit: https://github.com/tpm2-software/tpm2-tss/commit/6a9adcac623ffcff6bb08fb2c06fa7a6390546f4
    # Drop this when nixpkgs provides tpm2-tss 4.2.0 or newer, which includes the commit.
    # Last checked: 2026-08-02.
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
