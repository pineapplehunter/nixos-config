{
  flake.homeModules.pi-coding-agent =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      enabled = config.programs.pi-coding-agent.codexHost.enable;
      state = "${config.home.homeDirectory}/.local/state/pi-codex-host";
      codexImages = import ./codex-images.nix { inherit pkgs; };
      codexHostPackage = import ./codex-host.nix { inherit pkgs codexImages; };
      codexHost = "${codexHostPackage}/codex_host.mts";
    in
    {
      options.programs.pi-coding-agent.codexHost.enable =
        lib.mkEnableOption "sandboxed Pi using host-only Codex credentials";

      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        programs.pi-coding-agent.codexHost.enable = lib.mkDefault true;

        home = lib.mkIf enabled {
          packages = [ (import ./codex-auth.nix { inherit pkgs codexHost state; }) ];
          file = {
            ".pi/agent/extensions/codex-host-images.ts".text =
              ''export { default } from "${codexImages}/index.ts";'';
            ".pi/agent/skills/imagegen".source = "${codexImages}/skills/imagegen";
          };
        };

        systemd.user = lib.mkIf enabled {
          services.pi-codex-host = {
            Unit.Description = "Broker Codex requests for sandboxed Pi";
            Service = {
              ExecStart = lib.escapeShellArgs [
                (lib.getExe pkgs.nodejs)
                (toString codexHost)
                "serve"
                state
              ];
              UMask = "0077";
              NoNewPrivileges = true;
              PrivateTmp = true;
            };
          };

          sockets.pi-codex-host = {
            Unit.Description = "Socket for the host Codex broker for Pi";
            Socket = {
              ListenStream = "%t/pi-codex-host/broker.sock";
              DirectoryMode = "0700";
              SocketMode = "0600";
              RemoveOnStop = true;
            };
            Install.WantedBy = [ "sockets.target" ];
          };
        };
      };
    };
}
