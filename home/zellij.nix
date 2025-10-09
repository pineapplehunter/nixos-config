{
  flake.homeModules.zellij =
    { pkgs, ... }:
    {
      config = {
        programs.zellij = {
          enable = true;
          settings = {
            theme = "light";
            themes.light = {
              fg = "#DCD7BA";
              bg = "#1F1F28";
              red = "#C34043";
              green = "#76946A";
              yellow = "#FF9E3B";
              blue = "#0000FF";
              magenta = "#957FB8";
              orange = "#FFA066";
              cyan = "#7FB4CA";
              black = "#16161D";
              white = "#DCD7BA";
            };
          };
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
    };
}
