{
  flake.overlays.flatpak = final: prev: {
    # Custom workaround for an observed 30-second delay when starting any Flatpak app.
    # The root cause is unknown and there is no linked upstream issue or PR.
    # Drop this once the root cause is understood and fixed without disabling document portals.
    # Last checked: 2026-08-02.
    flatpak = prev.flatpak.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace common/flatpak-run.c \
          --replace-fail "if (!sandboxed && !(flags & FLATPAK_RUN_FLAG_NO_DOCUMENTS_PORTAL))" "" \
          --replace-fail "add_document_portal_args (bwrap, app_id, &doc_mount_path);" ""
      '';
    });
  };
}
