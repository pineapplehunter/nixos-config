{ config, pkgs, ... }: {
  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-emoji
      fira-code
      fira-code-symbols
      vistafonts
      (nerdfonts.override { fonts = [ "FiraCode" "DejaVuSansMono" ]; })
    ];
    fontDir.enable = true;
  };
}
