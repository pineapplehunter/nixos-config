{
  flake.overlays.rpi5 = final: prev: {
    # The pinned Raspberry Pi FFmpeg 8.0.1 fork references a field removed in
    # SVT-AV1 4.x, preventing it from building. There is no linked issue or PR.
    # Drop this when nixos-raspberrypi updates its FFmpeg fork for SVT-AV1 4.x.
    # Last checked: 2026-08-26.
    ffmpeg_8-headless = prev.ffmpeg_8-headless.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./patches/ffmpeg-svtav1-enable_adaptive_quantization.patch
      ];
    });
  };
}
