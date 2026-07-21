{
  flake.overlays.opencode = final: prev: {
    # Show elapsed time on the TUI spinner after 10 seconds.
    opencode = prev.opencode.overrideAttrs (old: {
      patches = [
        ./patches/opencode-elapsed.patch
      ];
    });
  };
}
