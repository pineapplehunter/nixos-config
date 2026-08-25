{
  flake.overlays.linux-latest = final: prev: {
    # Build machine-specific kernels with microarchitecture tuning for better performance.
    # There is no linked upstream issue or PR; implementation reference:
    # https://www.reddit.com/r/NixOS/comments/1b77j9i/build_with_marchnative_and_etc/
    # Drop individual variants when their corresponding machines no longer use them.
    # Last checked: 2026-08-26.
    linux_latest_arrowlake = prev.linux_latest.overrideAttrs (old: {
      env = (old.env or { }) // {
        KCFLAGS = "-march=arrowlake -mtune=arrowlake";
      };
    });
    linux_latest_tigerlake = prev.linux_latest.overrideAttrs (old: {
      env = (old.env or { }) // {
        KCFLAGS = "-march=tigerlake -mtune=tigerlake";
      };
    });
    linux_latest_znver1 = prev.linux_latest.overrideAttrs (old: {
      env = (old.env or { }) // {
        KCFLAGS = "-march=znver1 -mtune=znver1";
      };
    });
  };
}
