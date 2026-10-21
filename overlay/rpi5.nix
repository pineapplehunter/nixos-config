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

    # nixos-raspberrypi still pins the 8.0.1 RPi fork. Its latest 8.1.x branch
    # is 8.1.2 (nixpkgs has moved to 8.1.3); track it for the upstream SVT-AV1
    # 4.x compatibility fix while preserving the RPi V4L2 changes.
    # Recheck available branches and revision here on the next update:
    # https://github.com/jc-kynesim/rpi-ffmpeg/branches/all
    # https://github.com/jc-kynesim/rpi-ffmpeg/tree/test/8.1.2/main
    # https://github.com/jc-kynesim/rpi-ffmpeg/commit/f60aae17021abae85b1ba9759e8b2da33f723902
    # Drop this source override once nixos-raspberrypi updates ffmpeg_8-rpi.
    ffmpeg_8-headless = prev.ffmpeg_8-headless.overrideAttrs (old: rec {
      version = "8.1.2";
      src = final.fetchFromGitHub {
        owner = "jc-kynesim";
        repo = "rpi-ffmpeg";
        rev = "f60aae17021abae85b1ba9759e8b2da33f723902";
        hash = "sha256-mPcARTkZAAljvmsahC/HTe5eK+E1brbEGb2Q1X37egg=";
      };
      # The input appends this 8.0/8.0.1 fix unconditionally, but it is already
      # part of the 8.1.2 source and no longer applies.
      patches = builtins.filter (
        patch: !final.lib.hasInfix "unbreak-hardcoded-tables" (builtins.baseNameOf (toString patch))
      ) (old.patches or [ ]);
    });
  };
}
