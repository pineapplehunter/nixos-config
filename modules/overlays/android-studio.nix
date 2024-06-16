{ prev, ... }: {
  android-studio = prev.android-studio.overrideAttrs {
    preferLocalBuild = true;
  };
}
