{
  flake.overlays.rpi5 = final: prev: {
    # Keep the Raspberry Pi fork: it carries Pi-specific pipelines, tuning data,
    # and sensor support not yet included in the upstream libcamera release.
    # nixos-raspberrypi's older 0.7.0 fork no longer accepts flags inherited
    # from nixpkgs' 0.7.2 expression, so use the matching Raspberry Pi release.
    # https://github.com/raspberrypi/libcamera/releases/tag/v0.7.2+rpt20260817
    # Drop this version override once nixos-raspberrypi supplies a compatible fork.
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
    # SVT-AV1 4.x, preventing it from building. Backport upstream's field rename
    # to preserve constant-QP behavior (disabling adaptive quantization).
    # https://github.com/FFmpeg/FFmpeg/commit/a5d4c398b411a00ac09d8fe3b66117222323844c
    # Drop this when nixos-raspberrypi includes that fix in its FFmpeg fork.
    ffmpeg_8-headless = prev.ffmpeg_8-headless.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./patches/ffmpeg-svtav1-enable_adaptive_quantization.patch
      ];
    });
  };
}
