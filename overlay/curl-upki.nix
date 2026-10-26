{
  flake.overlays.curl-upki = final: prev: {
    # Keep this opt-in: replacing curl would rebuild its many reverse dependencies.
    # Use the OpenSSL integration from the upstream discussion, rebased for curl 8.22.
    # https://github.com/curl/curl/discussions/21594
    # https://github.com/ctz/curl/commit/1df819c0d27459f15974cf7286d914bf860309f5
    # Requires the cache populated by services.upki; no curlrc setting is needed.
    # Drop the patch when this integration is available in nixpkgs curl.
    curl-upki = prev.curlFull.overrideAttrs (old: {
      pname = "curl-upki";
      patches = (old.patches or [ ]) ++ [ ./patches/curl-upki.patch ];
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.autoreconfHook ];
      propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [ final.upki ];
      configureFlags = (old.configureFlags or [ ]) ++ [ "--with-upki" ];
    });
  };
}
