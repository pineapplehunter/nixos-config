{
  flake.overlays.ghostty = final: prev: {
    # Experimental pixel scrolling, ported to Ghostty 1.3.1 from:
    # https://github.com/ghostty-org/ghostty/discussions/3206#discussioncomment-19000959
    # Remove when upstream ships native smooth scrolling. This is a shader-based
    # approximation: exposed edge rows are missing and clicks snap to the grid.
    # Included in the default overlay; home/ghostty.nix enables the installed
    # shader without continuous animation. Remove its custom-shader setting to
    # disable the visual effect. Review this patch whenever Ghostty is upgraded.
    #
    # Precision scroll events shift the viewport by the fractional row remainder.
    # Alternate-screen apps, mouse-reporting apps, and selections stay on the
    # cell grid. Typing or clicking resets the offset; clicking snaps text before
    # hit-testing rather than supporting fractional-row selection.
    # This does not render the extra edge row, correct hover hit-testing for
    # shifted text, or add momentum or elastic overscroll. Ordinary mouse-wheel
    # scrolling stays line-based.
    ghostty = prev.ghostty.overrideAttrs (prevAttrs: {
      patches = (prevAttrs.patches or [ ]) ++ [ ./patches/ghostty-smooth-scroll.patch ];
      postInstall = (prevAttrs.postInstall or "") + ''
        install -Dm644 ${./shaders/ghostty-smooth-scroll.glsl} \
          $out/share/ghostty/shaders/smooth-scroll.glsl
      '';
    });
  };
}
