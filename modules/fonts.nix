{
  flake.nixosModules.fonts =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.my.common-fonts.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable common fonts";
      };

      config.fonts.packages = lib.mkIf config.my.common-fonts.enable [
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
