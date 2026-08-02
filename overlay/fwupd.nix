{
  flake.overlays.fwupd = final: prev: {
    # Can be dropped when https://github.com/nix-community/lanzaboote/issues/591 is fixed.
    fwupd = prev.fwupd.overrideAttrs (old: {
      mesonFlags =
        builtins.filter (flag: !(final.lib.hasPrefix "-Defi_app_location=" flag)) (old.mesonFlags or [ ])
        ++ [ (final.lib.mesonOption "efi_app_location" "/run/fwupd-efi") ];
    });
  };
}
