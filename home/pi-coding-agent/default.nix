{ inputs, ... }:
{
  flake.homeModules.pi-coding-agent =
    { pkgs, lib, ... }:
    let
      isLinux = pkgs.stdenv.hostPlatform.isLinux;
      skillPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]);

      piPackages = [
        "npm:@narumitw/pi-usage"
        "npm:pi-web-access"
        "npm:pi-codex-image-gen"
      ];

      updatePiSettings = pkgs.writers.writePython3Bin "update-pi-settings" { } (
        lib.readFile ./update-settings.py
      );

      anthropicSkillNames = [
        "algorithmic-art"
        "canvas-design"
        "discernment-nudge"
        "doc-coauthoring"
        "docx"
        "frontend-design"
        "internal-comms"
        "pdf"
        "pptx"
        "theme-factory"
        "webapp-testing"
        "xlsx"
      ];

      anthropicSkills = pkgs.runCommand "anthropic-skills" { } ''
        mkdir -p "$out"
        for skill in ${lib.escapeShellArgs anthropicSkillNames}; do
          cp -R "${inputs.anthropic-skills}/skills/$skill" "$out/"
        done
      '';

      rawWrapper = pkgs.writers.writePython3Bin "bubble-wrapper" {
        libraries = [ pkgs.python3Packages.pygobject3 ];
      } (lib.readFile ./wrapping.py);

      clipboardClient = pkgs.writers.writePython3Bin "wl-copy" {
        libraries = [ pkgs.python3Packages.pygobject3 ];
      } (lib.readFile ./clipboard_client.py);

      clipboardDaemon = pkgs.writers.writePython3Bin "pi-clipboardd" {
        libraries = [ pkgs.python3Packages.pygobject3 ];
      } (lib.readFile ./clipboard_daemon.py);

      portalClient = pkgs.writers.writePython3Bin "pi-portal-client" {
        libraries = [ pkgs.python3Packages.pygobject3 ];
      } (lib.readFile ./portal_client.py);

      portalClients = pkgs.runCommand "pi-portal-clients" { } ''
        mkdir -p "$out/bin" "$out/libexec"
        ln -s ${lib.getExe' portalClient "pi-portal-client"} "$out/libexec/pi-portal-client"
        for command in pi-open-uri pi-choose-file; do
          ln -s ../libexec/pi-portal-client "$out/bin/$command"
        done
      '';

      sandboxTools = pkgs.buildEnv {
        name = "pi-sandbox-tools";
        paths = [
          pkgs.bash
          pkgs.coreutils
          pkgs.diffutils
          pkgs.fd
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

      pueueConfig = pkgs.writeText "pi-pueue.yml" (lib.readFile ./pueue.yml);

      piWithPueue = pkgs.writeShellApplication {
        name = "pi-with-pueue";
        runtimeInputs = [ pkgs.pueue ];
        text = builtins.replaceStrings [ "@PI_EXECUTABLE@" ] [ (lib.getExe pkgs.pi-coding-agent) ] (
          lib.readFile ./pi-with-pueue.sh
        );
      };

      piCodingAgentWrapped =
        if isLinux then
          pkgs.symlinkJoin {
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
          }
        else
          pkgs.pi-coding-agent;
    in
    {
      home.packages = [
        piCodingAgentWrapped
        skillPython
      ]
      ++ lib.optionals isLinux [ portalClients ];

      home.activation.piPackages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${lib.getExe updatePiSettings} \
          "$HOME/.pi/agent/settings.json" \
          ${lib.escapeShellArgs piPackages}
      '';

      systemd.user.services.pi-clipboard = lib.mkIf isLinux {
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

      xdg.dataFile."dbus-1/services/io.github.pineapplehunter.LocalClipboard1.service" = lib.mkIf isLinux {
        text = ''
          [D-BUS Service]
          Name=io.github.pineapplehunter.LocalClipboard1
          Exec=${lib.getExe clipboardDaemon} --wl-copy ${lib.getExe' pkgs.wl-clipboard "wl-copy"}
          SystemdService=pi-clipboard.service
        '';
      };

      home.file = {
        ".pi/agent/skills/anthropic".source = anthropicSkills;
        ".pi/agent/skills/flake.md".source = ./flake.md;
        ".pi/agent/skills/nix-build.md".source = ./nix-build.md;
        ".pi/agent/skills/nixpkgs.md".source = ./nixpkgs.md;
        ".pi/agent/skills/rust.md".source = ./rust.md;
        ".pi/agent/skills/skill-creator".source = ./skill-creator;
        ".pi/agent/skills/todo".source = ./todo;
      }
      // lib.optionalAttrs isLinux {
        ".pi/agent/AGENTS.md".text = ''
          # Public Repository Research

          When researching code in a public repository, prefer cloning and inspecting it locally over repeated remote searches.
          Use a shallow clone when history is not needed.
          Put the repository clones under /tmp.

          # Sandbox Environment
          You are running in a sandbox created with linux namespacing.
          For more information, see skill `sandbox-info`.
        '';
        ".pi/agent/extensions/nix-bash.ts".source = ./nix-bash.ts;
        ".pi/agent/extensions/nix-search.ts".source = ./nix-search.ts;
        ".pi/agent/extensions/notify.ts".source = ./notify.ts;
        ".pi/agent/extensions/portal.ts".source = ./portal.ts;
        ".local/share/applications/io.github.pineapplehunter.Pi.desktop".text = ''
          [Desktop Entry]
          Type=Application
          Name=Pi Coding Agent
          Exec=pi %u
          NoDisplay=true
          X-Flatpak=io.github.pineapplehunter.Pi
        '';
        ".pi/agent/skills/pueue.md".source = ./pueue.md;
        ".pi/agent/skills/sandbox-info.md".source = ./sandbox.md;
      };
    };
}
