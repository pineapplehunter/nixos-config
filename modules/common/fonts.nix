{ pkgs, ... }:
{
  fonts = {
    packages = builtins.attrValues {
      inherit (pkgs)
        noto-fonts
        noto-fonts-color-emoji
        fira-code-symbols
        vistafonts
        ubuntu-classic
        ubuntu-sans
        ubuntu-sans-mono
        ;
      inherit (pkgs.nerd-fonts)
        fira-code
        dejavu-sans-mono
        ;
    };
  };
}
