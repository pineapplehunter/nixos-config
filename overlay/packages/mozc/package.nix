{
  lib,
  fetchFromGitHub,
  qt6,
  pkg-config,
  bazel_8,
  ibus,
  withIbus ? false,
  unzip,
  xdg-utils,
  python3,
  libglvnd,
  libxcrypt-legacy,
  glib,
  stdenv,
  autoPatchelfHook,
  writableTmpDirAsHomeHook,
  lndir,
  makeDesktopItem,
  copyDesktopItems,

  dictionaries ? [ ],
  merge-ut-dictionaries,
}:
let
  pname = "mozc";
  version = "3.33.6133";

  src = fetchFromGitHub {
    owner = "google";
    repo = "mozc";
    tag = version;
    hash = "sha256-4ZrCIWoqYjoBwaoXq2QGajIQgWP0m2V3ozWQhZIq138=";
    fetchSubmodules = true;
  };

  bazel = bazel_8;

  nativeBuildInputs = [
    bazel
    copyDesktopItems
    lndir
    pkg-config
    python3
    qt6.wrapQtAppsHook
    unzip
    writableTmpDirAsHomeHook
  ];

  buildInputs = [
    libglvnd
    libxcrypt-legacy
    qt6.qtbase
  ]
  ++ lib.optionals withIbus [
    ibus
    glib
  ];

  includePath = lib.makeIncludePath buildInputs;
  libraryPath = lib.makeLibraryPath buildInputs;

  bazelArgs = [
    "--config=oss_linux"
    "--compilation_mode=opt"
    "--action_env=C_INCLUDE_PATH=${includePath}"
    "--action_env=CPLUS_INCLUDE_PATH=${includePath}"
    "--action_env=LIBRARY_PATH=${libraryPath}"
    # targets
    "unix/icons"
    "gui/tool:mozc_tool"
    "server:mozc_server"
    "unix/emacs:mozc_emacs_helper"
    "unix/emacs:mozc.el"
    "renderer/qt:mozc_renderer"
  ]
  ++ lib.optionals withIbus [
    "unix/ibus:gen_mozc_xml"
    "unix/ibus:ibus_mozc"
  ];

  # First stage of vendoring: run "bazel vendor" to download all external
  # dependencies, then clean up sandbox-specific symlinks and markers so the
  # output is reproducible (fixed-output derivation).
  vendorStage1 = stdenv.mkDerivation {
    pname = "${pname}-vendor-stage1";
    inherit
      src
      version
      nativeBuildInputs
      buildInputs
      ;

    outputHash = "sha256-Kk/gd8uZfJaYFvA1b4TLycg8mwfQICcgX4WbqYNZqvM=";
    outputHashAlgo = null;
    outputHashMode = "recursive";

    strictDeps = true;
    __structuredAttrs = true;

    env.USE_BAZEL_VERSION = bazel.version;

    buildPhase = ''
      runHook preBuild

      cd src

      bazel vendor \
        --lockfile_mode=update \
        --vendor_dir="$out/vendor_dir" \
        ${lib.escapeShellArgs bazelArgs}

      cp MODULE.bazel.lock "$out"

      echo "removing broken symlinks and markers..."
      find "$out" -type l -lname '/*' -print -delete
      find "$out" -xtype l -print -delete
      rm -vf "$out"/vendor_dir/@rules_python*.marker

      runHook postBuild
    '';
    dontInstall = true;
    dontFixup = true;
    dontWrapQtApps = true;
  };

  # Second stage of vendoring: patch Python shebangs in the vendored
  # rules_python files so generated stub scripts use the Nix store Python
  # path instead of /usr/bin/env.
  vendorDeps = stdenv.mkDerivation {
    name = "${pname}-vendor";
    inherit version buildInputs;

    strictDeps = true;
    __structuredAttrs = true;

    nativeBuildInputs = [ autoPatchelfHook ];

    dontWrapQtApps = true;
    src = vendorStage1;
    installPhase = ''
      runHook preInstall

      cp -r . "$out"
      substituteInPlace \
        "$out"/vendor_dir/rules_python*/python/private/py_runtime_info.bzl \
        "$out"/vendor_dir/rules_python*/python/private/py_executable.bzl \
        "$out"/vendor_dir/rules_python*/python/private/runtime_env_toolchain.bzl \
        --replace-fail "/usr/bin/env python3" "${lib.getExe python3}"
      patchShebangs "$out"

      for dir in "$out"/vendor_dir/*/; do
        echo "pin(\"@@$(basename "$dir")\")"
      done > "$out"/vendor_dir/VENDOR.bazel

      runHook postInstall
    '';
  };

  ut-dictionary = merge-ut-dictionaries.override { inherit dictionaries; };
in
stdenv.mkDerivation {
  inherit
    pname
    version
    src
    nativeBuildInputs
    buildInputs
    ;

  strictDeps = true;
  __structuredAttrs = true;

  env.USE_BAZEL_VERSION = bazel.version;

  postPatch = ''
    cd src

    substituteInPlace config.bzl \
      --replace-fail "/usr/bin/xdg-open" "${xdg-utils}/bin/xdg-open" \
      --replace-fail "/usr" "$out"

    # Copy vendor directory to pwd as links
    lndir "${vendorDeps}"
  ''
  + lib.optionalString (dictionaries != [ ]) ''
    cat ${ut-dictionary}/mozcdic-ut.txt >> data/dictionary_oss/dictionary00.txt
  '';

  buildPhase = ''
    runHook preBuild

    bazel build \
      --lockfile_mode=error \
      --vendor_dir=vendor_dir \
      ${lib.escapeShellArgs bazelArgs}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm555 "bazel-bin/server/mozc_server"           "$out/lib/mozc/mozc_server"
    install -Dm555 "bazel-bin/renderer/qt/mozc_renderer"    "$out/lib/mozc/mozc_renderer"
    install -Dm555 "bazel-bin/gui/tool/mozc_tool"           "$out/lib/mozc/mozc_tool"
    install -Dm555 "bazel-bin/unix/emacs/mozc_emacs_helper" "$out/bin/mozc_emacs_helper"
    install -Dm444 "unix/emacs/mozc.el"                     "$out/share/emacs/site-lisp/emacs-mozc/mozc.el"
    install -d "$out/share/icons/mozc/"
    unzip bazel-bin/unix/icons.zip -d "$out/share/icons/mozc/"
  ''
  + (lib.optionalString withIbus ''
    install -Dm555 "bazel-bin/unix/ibus/ibus_mozc"          "$out/lib/ibus-mozc/ibus-engine-mozc"
    install -Dm555 "bazel-bin/unix/ibus/mozc.xml"           "$out/share/ibus/component/mozc.xml"
    install -d "$out/share/ibus-mozc/"
    for icon in "$out"/share/icons/mozc/*.png
    do
      cp "$icon" "$out/share/ibus-mozc/"
    done
    mv "$out/share/ibus-mozc"/{mozc,product_icon}.png
  '')
  + ''
    runHook postInstall
  '';

  # create a desktop file for gnome-control-center
  # contents copied from ubuntu
  desktopItems = lib.optionals withIbus [
    (makeDesktopItem {
      name = "ibus-setup-mozc-jp";
      desktopName = "Mozc Setup";
      exec = "@out@/lib/mozc/mozc_tool --mode=config_dialog";
      type = "Application";
      startupNotify = true;
      noDisplay = true;
    })
  ];

  postFixup = lib.optionalString withIbus ''
    substituteInPlace "$out/share/applications/ibus-setup-mozc-jp.desktop" \
      --subst-var out
  '';

  passthru = {
    inherit vendorStage1 vendorDeps;
  };
  meta = {
    isIbusEngine = withIbus;
    description = "Japanese input method from Google";
    mainProgram = "mozc_emacs_helper";
    homepage = "https://github.com/google/mozc";
    license = lib.licenses.free;
    platforms = lib.platforms.linux;
    maintainers = with lib.maintainers; [
      pineapplehunter
    ];
  };
}
