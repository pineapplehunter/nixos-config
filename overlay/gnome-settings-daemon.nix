{ prev, ... }: {
  gnome-settings-daemon = prev.gnome.gnome-settings-daemon.overrideAttrs (old: {
    # I don't need sleep notifications!
    postPatch = (old.postPatch or "") + ''
      substituteInPlace plugins/power/gsd-power-manager.c \
        --replace-fail "show_sleep_warning (manager);" "if(0) show_sleep_warning (manager);"
    '';
  });
}
