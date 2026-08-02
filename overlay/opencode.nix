{
  flake.overlays.opencode = final: prev: {
    # Custom feature: show elapsed time on every TUI spinner after 10 seconds.
    # There is no linked upstream issue or PR.
    # Drop this when OpenCode provides equivalent elapsed-time spinner behavior.
    # Last checked: 2026-08-02.
    opencode = prev.opencode.overrideAttrs (old: {
      patches = [
        ./patches/opencode-elapsed.patch
      ];
    });
  };
}
