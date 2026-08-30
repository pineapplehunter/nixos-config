{
  flake.overlays.rpi5 = final: prev: {
    # Keep the Raspberry Pi fork: it carries Pi-specific pipelines, tuning data,
    # and sensor support not yet included in the upstream libcamera release.
    # nixos-raspberrypi's older 0.7.0 fork no longer accepts flags inherited
    # from nixpkgs' 0.7.2 expression, so use the matching Raspberry Pi release.
    libcamera_rpi = prev.libcamera_rpi.overrideAttrs (old: rec {
      version = "0.7.2+rpt20260817";
      src = final.fetchFromGitHub {
        owner = "raspberrypi";
        repo = "libcamera";
        rev = "v${version}";
        hash = "sha256-r3ste6OwCrNvgD0oAQ+XaoWYPNVJihFW1moPDueNtnM=";
      };
      meta = old.meta // {
        changelog = "https://github.com/raspberrypi/libcamera/releases/tag/v${version}";
      };
    });

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
