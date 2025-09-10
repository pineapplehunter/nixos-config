{
  lib,
  stdenv,
  fetchgit,
  pkg-config,
  util-linux,
  udevCheckHook,
  bash,
}:

stdenv.mkDerivation rec {
  pname = "bcache-tools";
  version = "1.1";

  src = fetchgit {
    url = "https://git.kernel.org/pub/scm/linux/kernel/git/colyli/bcache-tools.git";
    rev = "bcache-tools-${version}";
    hash = "sha256-8BiHC8qxk4otFPyKnvGNk57JSZytEOy51AGertWo2O0=";
  };

  nativeBuildInputs = [
    pkg-config
    udevCheckHook
  ];
  buildInputs = [ util-linux ];

  doInstallCheck = true;

  # * Remove broken install rules (they ignore $PREFIX) for stuff we don't need
  #   anyway (it's distro specific stuff).
  # * Fixup absolute path to modprobe.
  prePatch = ''
    sed -e "/INSTALL.*initramfs\/hook/d" \
        -e "/INSTALL.*initcpio\/install/d" \
        -e "/INSTALL.*dracut\/module-setup.sh/d" \
        -e "/INSTALL.*probe-bcache/d" \
        -i Makefile
    # Remove probe-bcache which will be handled by util-linux
    sed -e "/probe-bcache/d" \
        -e "s@.*bcache-register.*@RUN+=\"${bash}/bin/sh -c 'echo $tempnode > /sys/fs/bcache/register_quiet'\"@" \
        -i 69-bcache.rules
  '';

  makeFlags = [
    "PREFIX="
    "DESTDIR=$(out)"
  ];

  preInstall = ''
    mkdir -p "$out/sbin" "$out/lib/udev/rules.d" "$out/share/man/man8"
  '';

  meta = {
    description = "User-space tools required for bcache (Linux block layer cache)";
    longDescription = ''
      Bcache is a Linux kernel block layer cache. It allows one or more fast
      disk drives such as flash-based solid state drives (SSDs) to act as a
      cache for one or more slower hard disk drives.

      This package contains the required user-space tools.

      User documentation is in Documentation/bcache.txt in the Linux kernel
      tree.
    '';
    homepage = "https://www.kernel.org/doc/html/latest/admin-guide/bcache.html";
    license = lib.licenses.gpl2Only;
    maintainers = with lib.maintainers; [
      bjornfor
      pineapplehunter
    ];
    mainProgram = "bcache-tools";
    platforms = lib.platforms.linux;
  };
}
