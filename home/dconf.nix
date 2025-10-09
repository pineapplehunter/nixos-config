{
  flake.homeModules.dconf = {
    config.dconf.settings = {
      "org/gnome/desktop/applications/terminal" = {
        exec = "ghostty";
        exec-arg = "";
      };
      "org/gnome/desktop/wm/keybindings" = {
        close = [ "<Shift><Super>q" ];
      };
      "org/gnome/settings-daemon/plugins/media-keys" = {
        custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
        ];
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
        name = "Terminal";
        command = "ghostty";
        binding = "<Super>Return";
      };
      "com/github/stunkymonkey/nautilus-open-any-terminal" = {
        terminal = "ghostty";
        lockAll = true;
      };
    };
  };
}
