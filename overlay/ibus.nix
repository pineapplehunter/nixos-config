{
  flake.overlays.ibus = final: prev: {
    # Fix a use-after-free when overlapping engine switches cancel a startup request.
    # https://github.com/ibus/ibus/issues/2957
    # https://github.com/ibus/ibus/pull/2958
    # Keep only the runtime fix: IBus 1.5.34 lacks the newer Meson test layout.
    # Remove once the pinned IBus includes this fix (1.5.35-rc1 or later).
    ibus = prev.ibus.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        (final.fetchpatch {
          name = "ibus-engineproxy-cancel-use-after-free.patch";
          url = "https://github.com/ibus/ibus/commit/14ec1665333d74cc696453e4ba12bc10840dabd1.patch";
          includes = [ "bus/engineproxy.c" ];
          hash = "sha256-YeL/nRo92+mLKwcMD1LHemNI/EZSO+Xbs9EtdVebCO0=";
        })
      ];
    });
  };
}
