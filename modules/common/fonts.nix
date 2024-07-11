{ pkgs, ... }:
{
  fonts = {
    packages = with pkgs; [
      fira-code
      fira-code-symbols
      vistafonts
      ubuntu_font_family
      (nerdfonts.override {
        fonts = [
          "FiraCode"
          "DejaVuSansMono"
        ];
      })
    ];
  };
}
