{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    webcord
    slack
    super-productivity
    android-studio
    jdk
  ];
}
