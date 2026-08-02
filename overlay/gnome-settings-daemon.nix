{
  flake.overlays.gnome-settings-daemon = final: prev: {
    # Personal preference: suppress the sleep warning because it wakes the screen after dimming.
    # There is no linked upstream issue or PR.
    # Drop this when GNOME supports disabling the warning through an upstream setting.
    # Last checked: 2026-08-02.
    gnome-settings-daemon = prev.gnome-settings-daemon.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace plugins/power/gsd-power-manager.c \
          --replace-fail "show_sleep_warnings = TRUE" "show_sleep_warnings = FALSE"
      '';
    });
  };
}
