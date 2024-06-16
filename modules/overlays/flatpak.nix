{ prev, ... }: {
  flatpak = prev.flatpak.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace common/flatpak-run.c \
        --replace-fail "if (!sandboxed && !(flags & FLATPAK_RUN_FLAG_NO_DOCUMENTS_PORTAL))" "" \
        --replace-fail "add_document_portal_args (bwrap, app_id, &doc_mount_path);" ""
    '';
  });
}
