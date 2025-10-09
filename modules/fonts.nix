{
  flake.nixosModules.fonts =
    { pkgs, ... }:
    {
      fonts.packages = [
        pkgs.noto-fonts
        pkgs.noto-fonts-color-emoji
        pkgs.fira-code-symbols
        pkgs.ubuntu-classic
        pkgs.ubuntu-sans
        pkgs.ubuntu-sans-mono
        pkgs.nerd-fonts.fira-code
        pkgs.nerd-fonts.dejavu-sans-mono
      ];
    };
}
