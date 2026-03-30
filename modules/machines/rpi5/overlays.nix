final: prev: {
  libcamera_rpi = prev.libcamera_rpi.overrideAttrs (old: rec {
    version = "0.7.0+rpt20260205";
    src = final.fetchFromGitHub {
      owner = "raspberrypi";
      repo = "libcamera";
      rev = "v${version}";
      hash = "sha256-ZSKNeFDedqzcVxoLPap2dMjq+F3C1eQ+HikEKuGBOyM=";
    };
  });

  ffmpeg_8 = prev.ffmpeg_8.overrideAttrs rec {
    version = "8.1";
    patches = [ ];
    src = final.fetchFromGitHub {
      owner = "jc-kynesim";
      repo = "rpi-ffmpeg";
      rev = "n${version}";
      hash = "sha256-FdKhhCveEo5UodEoyUh3aBHABv3OT2VXmwBXE1ce3p0=";
    };
  };
}
