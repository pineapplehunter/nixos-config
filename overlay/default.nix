{
  inputs,
  lib,
  ...
}:
rec {
  default = lib.composeManyExtensions [
    stable
    custom
    removeDesktop
  ];

  removeDesktop =
    final: prev:
    let
      removeDesktopEntry =
        package:
        let
          inherit (package) version;
          pname = "${package.pname}-no-desktop";
        in
        final.runCommand "${pname}-${version}"
          {
            passthru = {
              inherit version pname;
              original = package;
            };
            preferLocalBuild = true;
          }
          ''
            cp -srL --no-preserve=mode ${package} $out
            rm -rfv $out/share/applications
          '';
    in
    {
      julia = removeDesktopEntry prev.julia;
      btop = removeDesktopEntry prev.btop;
      htop = removeDesktopEntry prev.htop;
      helix = removeDesktopEntry prev.helix;
      yazi = removeDesktopEntry prev.yazi;
      fish = removeDesktopEntry prev.fish;
    };

  custom = final: prev: {

    curl-http3 = prev.curl.override {
      http3Support = true;
      openssl = prev.quictls;
    };
    flatpak = prev.flatpak.overrideAttrs (old: {
      postPatch =
        (old.postPatch or "")
        + ''
          substituteInPlace common/flatpak-run.c \
            --replace-fail "if (!sandboxed && !(flags & FLATPAK_RUN_FLAG_NO_DOCUMENTS_PORTAL))" "" \
            --replace-fail "add_document_portal_args (bwrap, app_id, &doc_mount_path);" ""
        '';
    });
    android-studio = prev.android-studio.overrideAttrs {
      preferLocalBuild = true;
    };
    super-productivity = final.callPackage (
      inputs.nixpkgs-pineapplehunter-supprod + /pkgs/by-name/su/super-productivity/package.nix
    ) { };
    mqttx-cli = final.callPackage (
      inputs.nixpkgs-pineapplehunter-mqttx-cli + /pkgs/by-name/mq/mqttx-cli/package.nix
    ) { };
    gitify = final.callPackage (
      inputs.nixpkgs-pineapplehunter-gitify + /pkgs/by-name/gi/gitify/package.nix
    ) { };
    gnome = prev.gnome // {
      gnome-settings-daemon = prev.gnome.gnome-settings-daemon.overrideAttrs (old: {
        # I don't need sleep notifications!
        postPatch =
          (old.postPatch or "")
          + ''
            substituteInPlace plugins/power/gsd-power-manager.c \
              --replace-fail "show_sleep_warning (manager);" "if(0) show_sleep_warning (manager);"
          '';
      });
    };
    nix-search-cli = inputs.nix-search-cli.packages.${final.system}.default.overrideAttrs (old: {
      # fix non-standard version representation
      version = builtins.head (builtins.match ''[^0-9]*([0-9\.]+).*'' old.version);
    });
    npm-lockfile-fix = inputs.npm-lockfile-fix.packages.${final.system}.default.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./retry.patch
      ];
      meta = old.meta // {
        mainProgram = "npm-lockfile-fix";
      };
    });
  };

  stable =
    final: prev:
    let
      pkgs-stable = import inputs.nixpkgs-stable { inherit (final) system; };
    in
    {
      inherit (pkgs-stable)
        julia-bin
        ;
    };
}
