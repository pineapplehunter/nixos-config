final: prev: {
  libcamera_rpi = prev.libcamera_rpi.overrideAttrs (old: rec{
    version = "0.7.0+rpt20260205";
     src = final.fetchFromGitHub {
      owner = "raspberrypi";
      repo = "libcamera";
      rev = "v${version}";
      hash = "sha256-ZSKNeFDedqzcVxoLPap2dMjq+F3C1eQ+HikEKuGBOyM=";
    };
  });
}
