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
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ghostty/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/wayscriber/"
        ];
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ghostty" = {
        name = "Terminal";
        command = "ghostty";
        binding = "<Super>Return";
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/wayscriber" = {
        name = "Wayscriber";
        command = "wayscriber -a";
        binding = "<Super>w";
      };
      "com/github/stunkymonkey/nautilus-open-any-terminal" = {
        terminal = "ghostty";
        lockAll = true;
      };
    };
  };
}
