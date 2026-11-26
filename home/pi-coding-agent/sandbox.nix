{ config, ... }:
let
  mcpModule = config.flake.homeModules.mcp-dbus;
in
{
  flake.homeModules.pi-coding-agent =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      inherit (config.programs.pi-coding-agent) sandbox;

      sandboxPackageOption =
        description:
        lib.mkOption {
          inherit description;
          type = lib.types.package;
          internal = true;
        };

      mcpServers = lib.filterAttrs (_: server: server.enable) config.services.mcp-dbus.servers;
      mcpRegistrations = lib.mapAttrs (_: server: {
        command = lib.getExe pkgs.mcp-dbus-proxy;
        args = [
          "--service"
          server.busName
        ];
        exposure = "direct";
        timeout = 90;
      }) mcpServers;
      skillPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]);

      updatePiResources = pkgs.writers.writePython3Bin "pi-update-resources" { } (
        lib.readFile ./pi-update.py
      );
      piUpdate = pkgs.writeShellApplication {
        name = "pi-update";
        runtimeInputs = [
          pkgs.git
          pkgs.nodejs
        ];
        text = ''
          export PI_UPDATE_PI=${lib.getExe pkgs.pi-coding-agent}
          exec ${lib.getExe updatePiResources} "$@"
        '';
      };

      updateMcpSettings = pkgs.writers.writePython3Bin "update-pi-mcp" { } (lib.readFile ./update-mcp.py);

      rawWrapper =
        pkgs.writers.writePython3Bin "bubble-wrapper"
          {
            libraries = [ pkgs.python3Packages.dbus-next ];
          }
          (
            builtins.replaceStrings
              [ "MCP_BUS_NAMES = ()  # configured by Home Manager" ]
              [
                (
                  "MCP_BUS_NAMES = [\n"
                  + lib.concatMapStrings (server: "    ${builtins.toJSON server.busName},\n") (
                    lib.attrValues mcpServers
                  )
                  + "]"
                )
              ]
              (lib.readFile ./pineapplehunter/wrapper/wrapping.py)
          );

      githubFetchEnabled = config.programs.pi-coding-agent.githubFetch.enable;
      codexHostEnabled = config.programs.pi-coding-agent.codexHost.enable;

      portalClient = pkgs.writers.writePython3Bin "pi-portal-client" {
        libraries = [ pkgs.python3Packages.dbus-next ];
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
          piUpdate
          pkgs.bubblewrap
          pkgs.bash
          pkgs.coreutils
          pkgs.curl-upki
          pkgs.diffutils
          pkgs.fd
          pkgs.file
          pkgs.findutils
          pkgs.gawk
          pkgs.git
          pkgs.gnugrep
          pkgs.gnused
          pkgs.gnutar
          pkgs.helix
          pkgs.nix
          pkgs.nix-search-cli
          pkgs.nodejs
          pkgs.openssh
          pkgs.patch
          pkgs.pi-coding-agent
          pkgs.pueue
          pkgs.ripgrep
          pkgs.mcp-dbus-proxy
          sandbox.clipboardClient
          sandbox.gitSigningClient
          sandbox.remoteTicketClient
          skillPython
          portalClients
        ]
        ++ lib.optional githubFetchEnabled sandbox.githubFetchClient;
        pathsToLink = [ "/bin" ];
      };

      subagentRunner =
        pkgs.writers.writePython3Bin "pi-subagent-runner" { }
          ./pineapplehunter/tools/subagents/runner.py;

      subagent = pkgs.writers.writePython3Bin "pi-subagent" { } (
        builtins.replaceStrings [ "@SUBAGENT_RUNNER@" ] [ (toString subagentRunner) ] (
          lib.readFile ./pineapplehunter/tools/subagents/launcher.py
        )
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
            --set PI_SANDBOX_PATH ${lib.escapeShellArg "${sandboxTools}/bin"} \
            --set PI_GITHUB_FETCH_ENABLED ${if githubFetchEnabled then "1" else "0"} \
            --set PI_CODEX_HOST_ENABLED ${if codexHostEnabled then "1" else "0"} \
            --set PI_GIT_CONFIG ${sandbox.gitConfig}
        '';
      };

      piCodingAgentWrapped = pkgs.symlinkJoin {
        name = "pi-coding-agent-wrapped";
        paths = [ pkgs.pi-coding-agent ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          rm -rf "$out/bin"
          mkdir "$out/bin"
          makeWrapper "${lib.getExe' wrapper "bubble-wrapper"}" "$out/bin/pi" \
            --set EXECUTABLE "${lib.getExe pkgs.pi-coding-agent}" \
            --set PROJECT_ROOT_FILE flake.nix
        '';
      };
    in
    {
      imports = [ mcpModule ];

      options.programs.pi-coding-agent.sandbox = {
        clipboardClient = sandboxPackageOption "Clipboard client for the Pi sandbox.";
        gitSigningClient = sandboxPackageOption "Git signing client for the Pi sandbox.";
        gitConfig = sandboxPackageOption "Generated Git configuration for the Pi sandbox.";
        githubFetchClient = sandboxPackageOption "GitHub CLI shim for the Pi sandbox.";
      };

      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        programs.pi-coding-agent.package = piCodingAgentWrapped;

        home = {
          packages = [
            piCodingAgentWrapped
            piUpdate
            subagent
            skillPython
            portalClients
          ];

          activation.piMcpServers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            ${lib.getExe updateMcpSettings} \
              "$HOME/.pi/agent/mcp.json" \
              ${lib.escapeShellArg (builtins.toJSON mcpRegistrations)}
          '';

          file.".local/share/applications/io.github.pineapplehunter.Pi.desktop".text = ''
            [Desktop Entry]
            Type=Application
            Name=Pi Coding Agent
            Exec=pi %u
            NoDisplay=true
            X-Flatpak=io.github.pineapplehunter.Pi
          '';
        };
      };
    };
}
