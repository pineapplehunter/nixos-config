{
  flake.homeModules.pi-coding-agent =
    { pkgs, lib, ... }:
    let
      isLinux = pkgs.stdenv.hostPlatform.isLinux;
      rawWrapper = pkgs.writers.writePython3Bin "bubble-wrapper" {
        libraries = [ pkgs.python3Packages.pygobject3 ];
      } (lib.readFile ./wrapping.py);

      wrapper = pkgs.symlinkJoin {
        name = "bubble-wrapper";
        paths = [ rawWrapper ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram "$out/bin/bubble-wrapper" \
            --prefix PATH : ${
              lib.makeBinPath [
                pkgs.bubblewrap
                pkgs.pueue
                pkgs.xdg-dbus-proxy
              ]
            }
        '';
      };

      portalClient = pkgs.writers.writePython3Bin "pi-portal-client" {
        libraries = [ pkgs.python3Packages.pygobject3 ];
      } (lib.readFile ./portal_client.py);

      portalClients = pkgs.runCommand "pi-portal-clients" { } ''
        mkdir -p "$out/bin" "$out/libexec"
        ln -s ${lib.getExe' portalClient "pi-portal-client"} "$out/libexec/pi-portal-client"
        for command in pi-open-uri pi-open-file pi-choose-file; do
          ln -s ../libexec/pi-portal-client "$out/bin/$command"
        done
      '';

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
      home.packages = [ piCodingAgentWrapped ] ++ lib.optionals isLinux [ portalClients ];

      home.file = lib.mkIf isLinux {
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
        ".pi/agent/skills/flake.md".source = ./flake.md;
        ".pi/agent/skills/nix-build.md".source = ./nix-build.md;
        ".pi/agent/skills/nixpkgs.md".source = ./nixpkgs.md;
        ".pi/agent/skills/pueue.md".source = ./pueue.md;
        ".pi/agent/skills/rust.md".source = ./rust.md;
        ".pi/agent/skills/sandbox-info.md".source = ./sandbox.md;
      };
    };
}
