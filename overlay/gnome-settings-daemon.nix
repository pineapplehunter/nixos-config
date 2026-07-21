{
  flake.overlays.gnome-settings-daemon = final: prev: {
    # Remove sleep notification.  The notification wakes up the screen
    # after dimming.
    gnome-settings-daemon = prev.gnome-settings-daemon.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace plugins/power/gsd-power-manager.c \
          --replace-fail "show_sleep_warnings = TRUE" "show_sleep_warnings = FALSE"
      '';
    });
  };
}
