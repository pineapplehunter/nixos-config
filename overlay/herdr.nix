{
  flake.overlays.herdr = final: prev: {
    # Herdr 0.9.1 fails to link with binutils 2.46 on x86_64-linux:
    # ld.bfd reports ".eh_frame_hdr refers to overlapping FDEs". Use LLD
    # for the final Rust link; forcing LLVM for libghostty-vt alone did not help.
    # There is no linked upstream issue or PR for this local workaround.
    # Remove when the pinned Herdr/toolchain builds with the default linker again.
    herdr = prev.herdr.overrideAttrs (
      old:
      final.lib.optionalAttrs (final.stdenv.hostPlatform.system == "x86_64-linux") {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.lld ];
        env = (old.env or { }) // {
          RUSTFLAGS = (old.env.RUSTFLAGS or "") + " -C link-arg=-fuse-ld=lld";
        };
      }
    );
  };
}
