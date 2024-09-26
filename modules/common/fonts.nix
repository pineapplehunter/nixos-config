{ pkgs, ... }:
{
  fonts = {
    packages = builtins.attrValues {
      inherit (pkgs)
        noto-fonts
        noto-fonts-color-emoji
        fira-code
        fira-code-symbols
        vistafonts
        ubuntu-classic
        ubuntu-sans
        ubuntu-sans-mono
        ;
      nerdfonts = pkgs.nerdfonts.override {
        fonts = [
          "FiraCode"
          "DejaVuSansMono"
        ];
      };
    };
  };
}
