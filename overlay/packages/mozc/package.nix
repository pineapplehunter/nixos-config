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
  dictionaries ? [ ],
  merge-ut-dictionaries,
  python3,
  libglvnd,
  libxcrypt-legacy,
  glib,
  stdenv,
  gnugrep,
  autoPatchelfHook,
  writableTmpDirAsHomeHook,
}:
let
  bazel = bazel_8;

  ut-dictionary = merge-ut-dictionaries.override { inherit dictionaries; };

  pname = "mozc";
  version = "3.33.6133";
  src = fetchFromGitHub {
    owner = "google";
    repo = "mozc";
    tag = version;
    hash = "sha256-4ZrCIWoqYjoBwaoXq2QGajIQgWP0m2V3ozWQhZIq138=";
    fetchSubmodules = true;
  };

  buildInputsList = [
    libglvnd
    libxcrypt-legacy
    qt6.qtbase
  ]
  ++ lib.optionals withIbus [
    ibus
    glib
  ];

  nativeBuildInputsList = [
    bazel
    pkg-config
    python3
    qt6.wrapQtAppsHook
    unzip
    writableTmpDirAsHomeHook
  ];

  includePath = lib.makeIncludePath buildInputsList;
  libraryPath = lib.makeLibraryPath buildInputsList;

  cmdArgs = [
    "--config=oss_linux"
    "--compilation_mode=opt"
    "--action_env=C_INCLUDE_PATH=${includePath}"
    "--action_env=CPLUS_INCLUDE_PATH=${includePath}"
    "--action_env=LIBRARY_PATH=${libraryPath}"
  ];

  targets = [
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

  vendorStage1 = stdenv.mkDerivation {
    pname = "${pname}-vendor-stage1";
    inherit src version;

    outputHash = "sha256-9kpbuIdiH9pyDuILD6GZ88Mlc3rcA+4AFOAW0VbcFyE=";
    outputHashAlgo = null;
    outputHashMode = "recursive";

    strictDeps = true;
    __structuredAttrs = true;

    env.USE_BAZEL_VERSION = bazel.version;

    nativeBuildInputs = nativeBuildInputsList;
    buildInputs = buildInputsList;

    postPatch = ''
      cd src
    '';
    dontFixup = true;
    buildPhase = ''
      runHook preBuild

      mkdir vendor_dir
      bazel \
        --batch \
        --output_base \
        .bazel_output_base \
        vendor \
        --vendor_dir=vendor_dir \
        --lockfile_mode=update \
        ${lib.escapeShellArgs (cmdArgs ++ targets)}

      find vendor_dir -type l -lname "$HOME/*" -exec rm '{}' \;
      find vendor_dir -type l -lname "/private/var/tmp/*" -exec rm '{}' \;
      find vendor_dir -type l -lname "*.bazel_output_base/*" -exec rm '{}' \;
      find vendor_dir -name "bazel-external" -exec rm -f '{}' \;
      find vendor_dir -xtype l -exec rm '{}' \;
      (${gnugrep}/bin/grep -rI "$NIX_STORE/" vendor_dir --files-with-matches --include="*.marker" --null || true) \
        | xargs -0 --no-run-if-empty rm
      find vendor_dir -type l -lname "*.bazel_output_base*" -exec rm '{}' \; 2>/dev/null || true
      runHook postBuild
    '';
    installPhase = ''
      mkdir -p $out/vendor_dir
      cp -r --reflink=auto vendor_dir/* $out/vendor_dir
      cp MODULE.bazel.lock $out/ 2>/dev/null || true
      if [ -d .bazel_output_base/cache ]; then
        mkdir -p $out/bazel_cache
        cp -r --reflink=auto .bazel_output_base/cache/* $out/bazel_cache/ 2>/dev/null || true
      fi
    '';
    dontWrapQtApps = true;
  };

  vendorDeps = stdenv.mkDerivation {
    name = "${pname}-vendor";
    inherit version;

    strictDeps = true;
    __structuredAttrs = true;

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
    buildInputs = buildInputsList;

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

      runHook postInstall
    '';
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  strictDeps = true;
  __structuredAttrs = true;

  env.USE_BAZEL_VERSION = bazel.version;

  buildInputs = buildInputsList;
  nativeBuildInputs = nativeBuildInputsList;

  postPatch = ''
    cd src

    substituteInPlace config.bzl \
      --replace-fail "/usr/bin/xdg-open" "${xdg-utils}/bin/xdg-open" \
      --replace-fail "/usr" "$out"
  ''
  + lib.optionalString (dictionaries != [ ]) ''
    cat ${ut-dictionary}/mozcdic-ut.txt >> data/dictionary_oss/dictionary00.txt
  '';

  preConfigure = ''
    if [ -d "${vendorDeps}/vendor_dir" ]; then
      cp -r "${vendorDeps}/vendor_dir/." vendor_dir/
      chmod -R +w vendor_dir
      for dir in vendor_dir/*/; do
        echo "pin(\"@@$(basename "$dir")\")"
      done > vendor_dir/VENDOR.bazel
    fi
    if [ -f "${vendorDeps}/MODULE.bazel.lock" ]; then
      cp "${vendorDeps}/MODULE.bazel.lock" MODULE.bazel.lock
    fi
    if [ -d "${vendorDeps}/bazel_cache" ]; then
      mkdir -p .bazel_output_base
      cp -r "${vendorDeps}/bazel_cache" .bazel_output_base/
    fi
  '';

  buildPhase = ''
    runHook preBuild

    sed -i "s|/usr/bin/env python3|${lib.getExe python3}|g; s|__PYTHON3__|${lib.getExe python3}|g" \
      vendor_dir/rules_python*/python/private/py_runtime_info.bzl \
      vendor_dir/rules_python*/python/private/py_executable.bzl \
      vendor_dir/rules_python*/python/private/runtime_env_toolchain.bzl \
      2>/dev/null || true

    bazel ${
      lib.escapeShellArgs [
        "--batch"
        "--output_base"
        ".bazel_output_base"
      ]
    } build ${
      lib.escapeShellArgs (
        [ "--vendor_dir=vendor_dir" ] ++ cmdArgs ++ [ "--lockfile_mode=error" ] ++ targets
      )
    }

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
    for icon in $out/share/icons/mozc/*.png
    do
      cp $icon $out/share/ibus-mozc/
    done
    mv $out/share/ibus-mozc/{mozc,product_icon}.png
  '')
  + ''
    mkdir -p $out/share/applications
    cp ${./ibus-setup-mozc-jp.desktop} $out/share/applications/ibus-setup-mozc-jp.desktop
    substituteInPlace $out/share/applications/ibus-setup-mozc-jp.desktop \
      --replace-fail "@mozc@" "$out"

    runHook postInstall
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
