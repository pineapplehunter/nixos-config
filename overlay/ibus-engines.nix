{
  flake.overlays.ibus-engines = final: prev: {
    # Use this repository's newer Mozc and UT-dictionary builds in ibus-engines;
    # nixpkgs' engine attributes otherwise continue to reference its older packages.
    # Associated PR: https://github.com/NixOS/nixpkgs/pull/531687.
    # Drop this when the custom Mozc packages
    # are no longer needed or nixpkgs' ibus-engines provide equivalent versions.
    # Last checked: 2026-08-26.
    ibus-engines = prev.ibus-engines // {
      mozc = final.ibus-mozc;
      mozc-ut = final.ibus-mozc.override { mozc = final.mozc-ut; };
    };
  };
}
