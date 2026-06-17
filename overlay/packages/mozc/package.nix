{
  lib,
  fetchFromGitHub,
  qt6,
  pkg-config,
  bazel_8,
  xdg-utils,
  python3,
  libglvnd,
  libxcrypt-legacy,
  stdenv,
  writableTmpDirAsHomeHook,
  lndir,

  dictionaries ? [ ],
  merge-ut-dictionaries,
}:
let
  bazel = bazel_8;

  ut-dictionary = merge-ut-dictionaries.override { inherit dictionaries; };

  pname = "mozc-server";
  version = "3.33.6133";

  src = fetchFromGitHub {
    owner = "google";
    repo = "mozc";
    tag = version;
    hash = "sha256-4ZrCIWoqYjoBwaoXq2QGajIQgWP0m2V3ozWQhZIq138=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    bazel
    lndir
    pkg-config
    python3
    qt6.wrapQtAppsHook
    writableTmpDirAsHomeHook
  ];

  buildInputs = [
    libglvnd
    libxcrypt-legacy
    qt6.qtbase
  ];

  includePath = lib.makeIncludePath buildInputs;
  libraryPath = lib.makeLibraryPath buildInputs;

  bazelArgs = [
    "--config=oss_linux"
    "--config=stable_channel"
    "--config=release_build"
    "--action_env=C_INCLUDE_PATH=${includePath}"
    "--action_env=CPLUS_INCLUDE_PATH=${includePath}"
    "--action_env=LIBRARY_PATH=${libraryPath}"
    "gui/tool:mozc_tool"
    "server:mozc_server"
  ];

  bazelPythonPatch = ''
    local_runtime_repo = use_repo_rule(
        "@rules_python//python/local_toolchains:repos.bzl",
        "local_runtime_repo",
    )
    local_runtime_toolchains_repo = use_repo_rule(
        "@rules_python//python/local_toolchains:repos.bzl",
        "local_runtime_toolchains_repo",
    )

    local_runtime_repo(
        name = "local_python3",
        interpreter_path = "python3",
        on_failure = "fail",
    )

    local_runtime_toolchains_repo(
        name = "local_toolchains",
        runtimes = ["local_python3"],
    )

    register_toolchains("@local_toolchains//:all")
  '';

  # vendoring: run "bazel vendor" to download all external dependencies,
  # then clean up sandbox-specific symlinks and markers so the output
  # is reproducible (fixed-output derivation).
  vendorDeps = stdenv.mkDerivation (
    lib.fetchers.normalizeHash { } {
      pname = "${pname}-vendor";
      inherit
        src
        version
        nativeBuildInputs
        buildInputs
        ;

      hash = "sha256-yFw2DcwbzGETXlh84VtBHG0HLundx5VJV+qP7PDbMic=";
      outputHashMode = "recursive";

      strictDeps = true;
      __structuredAttrs = true;

      env.USE_BAZEL_VERSION = bazel.version;

      buildPhase = ''
        runHook preBuild

        cd src

        cat >> MODULE.bazel << EOF
        ${bazelPythonPatch}
        EOF

        bazel vendor --lockfile_mode=update --vendor_dir="$out/vendor_dir" ${lib.escapeShellArgs bazelArgs}
        cp MODULE.bazel.lock "$out"

        echo "removing broken symlinks and markers..."
        find "$out" -type l -lname '/*' -print -delete
        find "$out" -xtype l -print -delete
        rm -vrf "$out"/vendor_dir/*local_python3*

        runHook postBuild
      '';
      dontInstall = true;
      dontFixup = true;
      dontWrapQtApps = true;
    }
  );
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

    cat >> MODULE.bazel << EOF
    ${bazelPythonPatch}
    EOF

    substituteInPlace config.bzl \
      --replace-fail "/usr/bin/xdg-open" "${xdg-utils}/bin/xdg-open" \
      --replace-fail "/usr" "$out"

    cp -r --no-preserve=mode "${vendorDeps}"/* .
    substituteInPlace \
      vendor_dir/rules_python*/python/private/py_runtime_info.bzl \
      vendor_dir/rules_python*/python/private/py_executable.bzl \
      vendor_dir/rules_python*/python/private/runtime_env_toolchain.bzl \
      --replace-fail "/usr/bin/env python3" "${lib.getExe python3}"
    patchShebangs --build vendor_dir
    for dir in vendor_dir/*/; do
      echo "pin(\"@@$(basename "$dir")\")"
    done > vendor_dir/VENDOR.bazel
  ''
  + lib.optionalString (dictionaries != [ ]) ''
    cat ${ut-dictionary}/mozcdic-ut.txt >> data/dictionary_oss/dictionary00.txt
  '';

  buildPhase = ''
    runHook preBuild

    bazel build --lockfile_mode=error --vendor_dir=vendor_dir ${lib.escapeShellArgs bazelArgs}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm555 bazel-bin/server/mozc_server "$out/lib/mozc/mozc_server"
    install -Dm555 bazel-bin/gui/tool/mozc_tool "$out/lib/mozc/mozc_tool"

    runHook postInstall
  '';

  passthru = {
    inherit vendorDeps bazel bazelPythonPatch;
  };
  meta = {
    description = "Japanese input method from Google";
    homepage = "https://github.com/google/mozc";
    license = lib.licenses.free;
    platforms = lib.platforms.linux;
    maintainers = with lib.maintainers; [
      pineapplehunter
    ];
  };
}
