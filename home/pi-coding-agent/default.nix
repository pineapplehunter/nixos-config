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
      isLinux = pkgs.stdenv.hostPlatform.isLinux;
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

      clipboardClient = pkgs.writers.writePython3Bin "wl-copy" {
        libraries = [ pkgs.python3Packages.dbus-next ];
      } (lib.readFile ./pineapplehunter/wrapper/clipboard_client.py);

      clipboardDaemon = pkgs.writers.writePython3Bin "pi-clipboardd" {
        libraries = [ pkgs.python3Packages.dbus-next ];
      } (lib.readFile ./pineapplehunter/wrapper/clipboard_daemon.py);

      gitUser = config.programs.git.settings.user;
      gitPublicKey = config.programs.git.signing.key;
      gitSignClient = pkgs.writers.writePython3Bin "pi-git-sign" {
        libraries = [ pkgs.python3Packages.dbus-next ];
      } (lib.readFile ./pineapplehunter/wrapper/git_sign_client.py);
      gitSignDaemon = pkgs.writers.writePython3Bin "pi-git-signingd" {
        libraries = [ pkgs.python3Packages.dbus-next ];
      } (lib.readFile ./pineapplehunter/wrapper/git_sign_daemon.py);
      gitConfig = (pkgs.formats.gitIni { }).generate "pi-gitconfig" {
        user = {
          inherit (gitUser) name email;
          # Git requires a key selector; only the host broker chooses the key.
          signingKey = "pi-host-signer";
        };
        commit.gpgSign = true;
        gpg = {
          format = "ssh";
          ssh.program = lib.getExe gitSignClient;
        };
      };

      githubFetchEnabled = config.programs.pi-coding-agent.githubFetch.enable;
      githubFetchBus = "io.github.pineapplehunter.GitHubFetch1";
      ghShim =
        pkgs.writers.writePython3Bin "gh"
          {
            libraries = [ pkgs.python3Packages.dbus-next ];
          }
          (
            builtins.replaceStrings [ "@GIT@" ] [ (lib.getExe pkgs.git) ] (
              lib.readFile ./pineapplehunter/wrapper/github_fetch_client.py
            )
          );
      githubFetchDaemon = pkgs.writers.writePython3Bin "pi-github-fetchd" {
        libraries = [ pkgs.python3Packages.dbus-next ];
      } (lib.readFile ./pineapplehunter/wrapper/github_fetch_daemon.py);
      githubFetchCommand = lib.escapeShellArgs [
        (lib.getExe githubFetchDaemon)
        (lib.getExe pkgs.gh)
      ];

      codexHostEnabled = config.programs.pi-coding-agent.codexHost.enable;
      codexHostState = "${config.home.homeDirectory}/.local/state/pi-codex-host";
      codexImages = import ./codex-images.nix { inherit pkgs; };
      codexHostPackage = import ./codex-host.nix { inherit pkgs codexImages; };
      codexHost = "${codexHostPackage}/codex_host.mts";
      codexAuth = import ./codex-auth.nix {
        inherit pkgs codexHost;
        state = codexHostState;
      };

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
          clipboardClient
          gitSignClient
          skillPython
          portalClients
        ]
        ++ lib.optional githubFetchEnabled ghShim;
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
            --set PI_GIT_CONFIG ${gitConfig}
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
      options.programs.pi-coding-agent.githubFetch.enable =
        lib.mkEnableOption "sandboxed GitHub fetching via the host's gh login";
      options.programs.pi-coding-agent.codexHost.enable =
        lib.mkEnableOption "sandboxed Pi using host-only Codex credentials";
      config = lib.mkIf isLinux {
        assertions = [
          {
            assertion = config.programs.git.signing.format == "ssh" && lib.hasSuffix ".pub" gitPublicKey;
            message = "Pi's host signer requires an SSH public signing key (*.pub).";
          }
        ];
        programs.pi-coding-agent = {
          package = piCodingAgentWrapped;
          codexHost.enable = lib.mkDefault true;
          githubFetch.enable = lib.mkDefault true;
        };
        home = {
          packages = [
            piCodingAgentWrapped
            piUpdate
            subagent
            skillPython
            portalClients
          ]
          ++ lib.optional codexHostEnabled codexAuth;

          activation.piMcpServers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            ${lib.getExe updateMcpSettings} \
              "$HOME/.pi/agent/mcp.json" \
              ${lib.escapeShellArg (builtins.toJSON mcpRegistrations)}
          '';

          file = {
            ".pi/agent/extensions/codex-host-images.ts" = lib.mkIf codexHostEnabled {
              text = ''export { default } from "${codexImages}/index.ts";'';
            };
            ".pi/agent/skills/imagegen" = lib.mkIf codexHostEnabled {
              source = "${codexImages}/skills/imagegen";
            };
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

        systemd.user.services.pi-git-signing = {
          Unit.Description = "Sign attributed Pi commits with the host SSH key";
          Service = {
            Type = "dbus";
            BusName = "io.github.pineapplehunter.GitSign1";
            ExecStart = lib.escapeShellArgs [
              (lib.getExe gitSignDaemon)
              "--ssh-keygen"
              (lib.getExe' pkgs.openssh "ssh-keygen")
              "--key"
              gitPublicKey
              "--name"
              gitUser.name
              "--email"
              gitUser.email
            ];
          };
        };

        xdg.dataFile."dbus-1/services/io.github.pineapplehunter.GitSign1.service".text = ''
          [D-BUS Service]
          Name=io.github.pineapplehunter.GitSign1
          Exec=${lib.getExe gitSignDaemon} --ssh-keygen ${lib.getExe' pkgs.openssh "ssh-keygen"} --key ${lib.escapeShellArg gitPublicKey} --name ${lib.escapeShellArg gitUser.name} --email ${lib.escapeShellArg gitUser.email}
          SystemdService=pi-git-signing.service
        '';

        systemd.user.services.pi-github-fetch = lib.mkIf githubFetchEnabled {
          Unit.Description = "Broker allowlisted GitHub reads for sandboxed Pi";
          Service = {
            Type = "dbus";
            BusName = githubFetchBus;
            ExecStart = githubFetchCommand;
            NoNewPrivileges = true;
            PrivateTmp = true;
          };
        };

        xdg.dataFile."dbus-1/services/${githubFetchBus}.service" = lib.mkIf githubFetchEnabled {
          text = ''
            [D-BUS Service]
            Name=${githubFetchBus}
            Exec=${githubFetchCommand}
            SystemdService=pi-github-fetch.service
          '';
        };

        systemd.user.sockets.pi-codex-host = lib.mkIf codexHostEnabled {
          Unit.Description = "Socket for the host Codex broker for Pi";
          Socket = {
            ListenStream = "%t/pi-codex-host/broker.sock";
            DirectoryMode = "0700";
            SocketMode = "0600";
            RemoveOnStop = true;
          };
          Install.WantedBy = [ "sockets.target" ];
        };

        systemd.user.services.pi-codex-host = lib.mkIf codexHostEnabled {
          Unit.Description = "Broker Codex requests for sandboxed Pi";
          Service = {
            ExecStart = lib.escapeShellArgs [
              (lib.getExe pkgs.nodejs)
              (toString codexHost)
              "serve"
              codexHostState
            ];
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };
        };

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
      };
    };
}
