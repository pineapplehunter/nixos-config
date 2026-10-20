{
  flake.overlays.hplip = final: prev: {
    # Python derivations now use structured attributes, making makeWrapperArgs an
    # array. HPLIP's custom wrapper otherwise passes only its first element.
    # No linked upstream fix; remove once nixpkgs uses array expansion here.
    hplip = prev.hplip.overrideAttrs (oldAttrs: {
      preFixup =
        prev.lib.replaceStrings [ "$makeWrapperArgs" ] [ ''"''${makeWrapperArgs[@]}"'' ]
          oldAttrs.preFixup;
    });
  };
}
