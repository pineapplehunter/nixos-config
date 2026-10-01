{ inputs, ... }:
{
  flake.homeModules.pi-coding-agent =
    { pkgs, lib, ... }:
    let
      isLinux = pkgs.stdenv.hostPlatform.isLinux;
      skillPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]);

      localPiPackages = import ./packages.nix { inherit pkgs lib inputs; };
      piPackages = [
        "npm:@narumitw/pi-usage"
        "npm:pi-web-access"
        "npm:pi-codex-image-gen"
        "https://github.com/monotykamary/pi-double-esc@main"
        "https://github.com/pineapplehunter/pi-remote-server@main"
      ]
      ++ map toString localPiPackages;

      updatePiSettings = pkgs.writers.writePython3Bin "update-pi-settings" { } (
        lib.readFile ./update-settings.py
      );

      rawWrapper = pkgs.writers.writePython3Bin "bubble-wrapper" {
        libraries = [ pkgs.python3Packages.pygobject3 ];
      } (lib.readFile ./pineapplehunter/wrapper/wrapping.py);

      clipboardClient = pkgs.writers.writePython3Bin "wl-copy" {
        libraries = [ pkgs.python3Packages.pygobject3 ];
      } (lib.readFile ./pineapplehunter/wrapper/clipboard_client.py);

      clipboardDaemon = pkgs.writers.writePython3Bin "pi-clipboardd" {
        libraries = [ pkgs.python3Packages.pygobject3 ];
      } (lib.readFile ./pineapplehunter/wrapper/clipboard_daemon.py);

      portalClient = pkgs.writers.writePython3Bin "pi-portal-client" {
        libraries = [ pkgs.python3Packages.pygobject3 ];
      } (lib.readFile ./pineapplehunter/wrapper/portal_client.py);

      portalClients = pkgs.runCommand "pi-portal-clients" { } ''
        mkdir -p "$out/bin" "$out/libexec"
        ln -s ${lib.getExe' portalClient "pi-portal-client"} "$out/libexec/pi-portal-client"
        ln -s ../libexec/pi-portal-client "$out/bin/pi-choose-file"
      '';

      sandboxTools = pkgs.buildEnv {
        name = "pi-sandbox-tools";
        paths = [
          subagent
          subagentRunner
          pueueComplete
          pkgs.bubblewrap
          pkgs.bash
          pkgs.coreutils
          pkgs.diffutils
          pkgs.fd
          pkgs.file
          pkgs.findutils
          pkgs.gawk
          pkgs.git
          pkgs.gnugrep
          pkgs.gnused
          pkgs.helix
          pkgs.local-notify
          pkgs.nix
          pkgs.nix-search-cli
          pkgs.nodejs
          pkgs.openssh
          pkgs.patch
          pkgs.pi-coding-agent
          pkgs.pueue
          pkgs.ripgrep
          clipboardClient
          skillPython
          portalClients
        ];
        pathsToLink = [ "/bin" ];
      };

      subagentRunner =
        pkgs.writers.writePython3Bin "pi-subagent-runner" { }
          ./pineapplehunter/tools/subagents/runner.py;

      pueueComplete =
        pkgs.writers.writePython3Bin "pi-pueue-complete" { }
          ./pineapplehunter/wrapper/pueue-complete.py;

      subagent = pkgs.writers.writePython3Bin "pi-subagent" { } (
        builtins.replaceStrings
          [
            "@PUEUE_CONFIG@"
            "@SUBAGENT_RUNNER@"
            "@PI_PACKAGE@"
          ]
          [
            (toString pueueConfig)
            (toString subagentRunner)
            "${./pineapplehunter}"
          ]
          (lib.readFile ./pineapplehunter/tools/subagents/launcher.py)
      );

      wrapper = pkgs.symlinkJoin {
        name = "bubble-wrapper";
        paths = [ rawWrapper ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram "$out/bin/bubble-wrapper" \
            --prefix PATH : ${
              lib.makeBinPath [
                pkgs.bubblewrap
                pkgs.xdg-dbus-proxy
              ]
            } \
            --set PI_SANDBOX_PATH ${lib.escapeShellArg "${sandboxTools}/bin"}
        '';
      };

      pueueConfig = pkgs.writeText "pi-pueue.yml" (
        builtins.replaceStrings [ "@PUEUE_COMPLETE@" ] [ (lib.getExe pueueComplete) ] (
          lib.readFile ./pineapplehunter/wrapper/pueue.yml
        )
      );

      piWithPueue = pkgs.writeShellApplication {
        name = "pi-with-pueue";
        runtimeInputs = [ pkgs.pueue ];
        text = builtins.replaceStrings [ "@PI_EXECUTABLE@" ] [ (lib.getExe pkgs.pi-coding-agent) ] (
          lib.readFile ./pineapplehunter/wrapper/pi-with-pueue.sh
        );
      };

      piCodingAgentWrapped = pkgs.symlinkJoin {
        name = "pi-coding-agent-wrapped";
        paths = [ pkgs.pi-coding-agent ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          rm -rf "$out/bin"
          mkdir "$out/bin"
          makeWrapper "${lib.getExe' wrapper "bubble-wrapper"}" "$out/bin/pi" \
            --set EXECUTABLE "${lib.getExe piWithPueue}" \
            --set PROJECT_ROOT_FILE flake.nix \
            --set PUEUE_CONFIG_PATH "${pueueConfig}"
          makeWrapper "${lib.getExe' wrapper "bubble-wrapper"}" "$out/bin/pi-work" \
            --set EXECUTABLE "${lib.getExe piWithPueue}" \
            --set PROJECT_ROOT_FILE flake.nix \
            --set PUEUE_CONFIG_PATH "${pueueConfig}" \
            --set PI_WRAPPER_PROFILE work
        '';
      };
    in
    lib.mkIf isLinux {
      home.packages = [
        piCodingAgentWrapped
        subagent
        skillPython
        portalClients
      ];

      home.activation.piPackages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${lib.getExe updatePiSettings} \
          "$HOME/.pi/agent/settings.json" \
          ${lib.escapeShellArgs piPackages}
      '';

      systemd.user.services.pi-clipboard = {
        Unit = {
          Description = "Copy text from Pi to the host clipboard";
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "dbus";
          BusName = "io.github.pineapplehunter.LocalClipboard1";
          ExecStart = "${lib.getExe clipboardDaemon} --wl-copy ${lib.getExe' pkgs.wl-clipboard "wl-copy"}";
        };
      };

      xdg.dataFile."dbus-1/services/io.github.pineapplehunter.LocalClipboard1.service" = {
        text = ''
          [D-BUS Service]
          Name=io.github.pineapplehunter.LocalClipboard1
          Exec=${lib.getExe clipboardDaemon} --wl-copy ${lib.getExe' pkgs.wl-clipboard "wl-copy"}
          SystemdService=pi-clipboard.service
        '';
      };

      home.file = {
        ".pi/agent/AGENTS.md".text = ''
          Prefer shallow clones in /tmp over repeated remote searches of public repositories.
          If a file or tool is missing, see skill `sandbox-info`.
          Nix tooling is available; use `nix develop` or `nix shell` for project tools.
        '';
        ".local/share/applications/io.github.pineapplehunter.Pi.desktop".text = ''
          [Desktop Entry]
          Type=Application
          Name=Pi Coding Agent
          Exec=pi %u
          NoDisplay=true
          X-Flatpak=io.github.pineapplehunter.Pi
        '';
      };
    };
}
