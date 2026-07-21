{
  flake.homeModules.pi-coding-agent =
    { pkgs, lib, ... }:
    let
      isLinux = pkgs.stdenv.hostPlatform.isLinux;
      wrapper = pkgs.writeShellApplication {
        name = "bubble-wrapper";
        runtimeInputs = [ pkgs.bubblewrap ];
        text = lib.readFile ./wrapping.sh;
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
              makeWrapper "${lib.getExe wrapper}" "$out/bin/pi" \
                --set EXECUTABLE "${lib.getExe pkgs.pi-coding-agent}" \
                --set PROJECT_ROOT_FILE flake.nix
            '';
          }
        else
          pkgs.pi-coding-agent;
    in
    {
      home.packages = [ piCodingAgentWrapped ];

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
        ".pi/agent/skills/flake.md".source = ./flake.md;
        ".pi/agent/skills/nix-build.md".source = ./nix-build.md;
        ".pi/agent/skills/nixpkgs.md".source = ./nixpkgs.md;
        ".pi/agent/skills/rust.md".source = ./rust.md;
        ".pi/agent/skills/sandbox-info.md".source = ./sandbox.md;
      };
    };
}
