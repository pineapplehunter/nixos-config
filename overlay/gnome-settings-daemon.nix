{
  flake.overlays.gnome-settings-daemon = final: prev: {
    # Personal preference: suppress the sleep warning because it wakes the screen after dimming.
    # Upstream issue: https://gitlab.gnome.org/GNOME/gnome-settings-daemon/-/issues/874
    # Drop this when GNOME supports disabling only this warning through an upstream setting.
    gnome-settings-daemon = prev.gnome-settings-daemon.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace plugins/power/gsd-power-manager.c \
          --replace-fail "show_sleep_warnings = TRUE" "show_sleep_warnings = FALSE"
      '';
    });
  };
}
