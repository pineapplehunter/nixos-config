{
  flake.overlays.ghostty = final: prev: {
    # Experimental pixel scrolling, ported to Ghostty 1.3.1 from:
    # https://github.com/ghostty-org/ghostty/discussions/3206#discussioncomment-19000959
    # Remove when upstream ships native smooth scrolling. This is a shader-based
    # approximation: exposed edge rows are missing and clicks snap to the grid.
    ghostty = prev.ghostty.overrideAttrs (prevAttrs: {
      patches = (prevAttrs.patches or [ ]) ++ [ ./patches/ghostty-smooth-scroll.patch ];
      postInstall = (prevAttrs.postInstall or "") + ''
        install -Dm644 ${./shaders/ghostty-smooth-scroll.glsl} \
          $out/share/ghostty/shaders/smooth-scroll.glsl
      '';
    });
  };
}
