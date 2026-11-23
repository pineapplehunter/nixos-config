{
  flake.homeModules.pi-coding-agent =
    { pkgs, lib, ... }:
    let
      nixProxyPackage =
        if lib.versionAtLeast pkgs.nix.version "2.36" then pkgs.nix else pkgs.nixVersions.latest;
    in
    {
      config.systemd.user = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        services."pi-nix-daemon@" = {
          Unit.Description = "Proxy a Pi Nix daemon connection as untrusted";
          Service = {
            # Handle the accepted socket on stdio without setting up build cgroups.
            ExecStart = lib.escapeShellArgs [
              (lib.getExe' nixProxyPackage "nix-daemon")
              "--stdio"
              "--store"
              "unix:///nix/var/nix/daemon-socket/socket"
              "--force-untrusted"
            ];
            StandardInput = "socket";
            StandardOutput = "socket";
            StandardError = "journal";
          };
        };

        sockets.pi-nix-daemon = {
          Unit.Description = "Socket for the untrusted Pi Nix daemon proxy";
          Socket = {
            ListenStream = "%t/pi-nix-daemon/socket";
            Accept = true;
            DirectoryMode = "0700";
            SocketMode = "0600";
            RemoveOnStop = true;
          };
          Install.WantedBy = [ "sockets.target" ];
        };
      };
    };
}
