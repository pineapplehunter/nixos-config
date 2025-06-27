{ pkgs, ... }:
{
  config = {
    programs.zellij = {
      enable = true;
      settings = import ./zellij-config.nix;
      # disable auto startup
      enableZshIntegration = false;
      enableFishIntegration = false;
      enableBashIntegration = false;
    };

    home.packages = with pkgs; [
      file
      chafa
      p7zip
      ripgrep
      zoxide
      fzf
      imagemagick
    ];
  };
}
