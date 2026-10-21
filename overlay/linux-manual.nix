{
  flake.overlays.linux-manual = final: prev: {
    # Linux 7.3's sphinx-build-wrapper reads srctree before setting its default.
    # nixpkgs invokes it directly rather than through the kernel Makefile:
    # https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/by-name/li/linux-manual/package.nix
    # https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/tools/docs/sphinx-build-wrapper?h=v7.3
    # Remove once nixpkgs supplies srctree or the wrapper initializes it first.
    linux-manual = prev.linux-manual.overrideAttrs (oldAttrs: {
      preBuild = (oldAttrs.preBuild or "") + ''
        export srctree="$PWD"
      '';
    });
  };
}
