{
  flake.overlays.btrfs-assistant = final: prev: {
    # Keep native Qt translation tools out of the host-side plugin search path.
    # Without strictDeps, wrapQtAppsHook includes qttools and its QML dependencies
    # in the runtime wrapper even though they are only needed during the build.
    # Track the dependency declarations in nixpkgs:
    # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/bt/btrfs-assistant/package.nix
    # Remove this overlay when upstream enables strict dependency separation.
    # This does not fix the transitive dbus.dev/libdrm.dev references in qtbase
    # and mesa-libgbm; those require changes to the shared packages themselves.
    btrfs-assistant = prev.btrfs-assistant.overrideAttrs {
      strictDeps = true;
    };
  };
}
