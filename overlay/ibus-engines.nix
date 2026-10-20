{
  flake.overlays.ibus-engines = final: prev: {
    # Use this repository's newer Mozc and UT-dictionary builds in ibus-engines;
    # nixpkgs' engine attributes still pass withIbus, which the split packages
    # no longer accept.
    # Follow the contents of https://github.com/NixOS/nixpkgs/pull/531687 for
    # Mozc and its split IBus frontend, including untagged source revisions,
    # vendor hashes, and packaging changes; do not track Google tags/HEAD.
    # Dictionary sources and merger changes follow PR #570751 instead:
    # https://github.com/NixOS/nixpkgs/pull/570751 (see mozc-dictionaries.nix).
    # Drop this when the custom Mozc packages
    # are no longer needed or nixpkgs' ibus-engines provide equivalent versions.
    ibus-engines = prev.ibus-engines // {
      mozc = final.ibus-mozc;
      mozc-ut = final.ibus-mozc.override { mozc = final.mozc-ut; };
    };
  };
}
