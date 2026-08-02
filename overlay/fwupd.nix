{
  flake.overlays.fwupd = final: prev: {
    # Make fwupd load Lanzaboote's signed EFI app from /run instead of the Nix store.
    # Tracking issue: https://github.com/nix-community/lanzaboote/issues/591
    # Drop this when Lanzaboote handles fwupd's efi_app_location Meson option itself.
    # Last checked: 2026-08-02.
    fwupd = prev.fwupd.overrideAttrs (old: {
      mesonFlags =
        builtins.filter (flag: !(final.lib.hasPrefix "-Defi_app_location=" flag)) (old.mesonFlags or [ ])
        ++ [ (final.lib.mesonOption "efi_app_location" "/run/fwupd-efi") ];
    });
  };
}
