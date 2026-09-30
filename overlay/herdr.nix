{
  flake.overlays.herdr = final: prev: {
    # Herdr 0.9.1 fails to link with binutils 2.46 on x86_64 and aarch64 Linux:
    # ld.bfd reports overlapping FDEs and, on aarch64, invalid debug relocations
    # in libghostty-vt's compiler_rt.o. Use LLD for the final Rust link.
    # There is no linked upstream issue or PR for this local workaround.
    # Remove when the pinned Herdr/toolchain builds with the default linker again.
    herdr = prev.herdr.overrideAttrs (
      old:
      final.lib.optionalAttrs final.stdenv.hostPlatform.isLinux {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.lld ];
        env = (old.env or { }) // {
          RUSTFLAGS = (old.env.RUSTFLAGS or "") + " -C link-arg=-fuse-ld=lld";
        };
      }
    );
  };
}
