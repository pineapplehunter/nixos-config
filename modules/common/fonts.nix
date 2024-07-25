{ pkgs, ... }:
{
  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      fira-code
      fira-code-symbols
      vistafonts
      ubuntu-classic
      ubuntu-sans
      ubuntu-sans-mono
      (nerdfonts.override {
        fonts = [
          "FiraCode"
          "DejaVuSansMono"
        ];
      })
    ];
  };
}
