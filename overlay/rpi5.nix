{
  flake.overlays.rpi5 = final: prev: {
    # Keep the Raspberry Pi fork: it carries Pi-specific pipelines, tuning data,
    # and sensor support not yet included in the upstream libcamera release.
    # nixos-raspberrypi pins 0.7.0+rpt20260205, which does not accept flags
    # inherited from nixpkgs' newer expression; track the latest Raspberry Pi
    # release until its package expression is compatible.
    # https://github.com/raspberrypi/libcamera/releases/tag/v0.7.2+rpt20261009
    # Drop this version override once nixos-raspberrypi supplies a compatible fork.
    libcamera_rpi = prev.libcamera_rpi.overrideAttrs (old: rec {
      version = "0.7.2+rpt20261009";
      src = final.fetchFromGitHub {
        owner = "raspberrypi";
        repo = "libcamera";
        rev = "v${version}";
        hash = "sha256-R5zRsio+Mrn2Fdr+9aGy1B0O53OEEQofamfim/rAQ10=";
      };
      meta = old.meta // {
        changelog = "https://github.com/raspberrypi/libcamera/releases/tag/v${version}";
      };
    });

    # The RPi package replaces nixpkgs' FFmpeg 8.1.2 source with its 8.0.1
    # fork, but inherits the 8.1.2 patch list (which omits nixpkgs' 4.x
    # compatibility patch). The fork still references a field removed in
    # SVT-AV1 4.x; backport the rename to preserve constant-QP behavior
    # (disabling adaptive quantization).
    # https://github.com/FFmpeg/FFmpeg/commit/a5d4c398b411a00ac09d8fe3b66117222323844c
    # Drop this when nixos-raspberrypi includes that fix in its FFmpeg fork.
    ffmpeg_8-headless = prev.ffmpeg_8-headless.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./patches/ffmpeg-svtav1-enable_adaptive_quantization.patch
      ];
    });
  };
}
