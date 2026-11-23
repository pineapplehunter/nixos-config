{
  flake.homeModules.pi-coding-agent =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      enabled = config.programs.pi-coding-agent.githubFetch.enable;
      busName = "io.github.pineapplehunter.GitHubFetch1";
      daemon = pkgs.writers.writePython3Bin "pi-github-fetchd" {
        libraries = [ pkgs.python3Packages.dbus-next ];
      } (lib.readFile ./pineapplehunter/wrapper/github_fetch_daemon.py);
      command = lib.escapeShellArgs [
        (lib.getExe daemon)
        (lib.getExe pkgs.gh)
      ];
    in
    {
      options.programs.pi-coding-agent.githubFetch.enable =
        lib.mkEnableOption "sandboxed GitHub fetching via the host's gh login";

      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        programs.pi-coding-agent = {
          githubFetch.enable = lib.mkDefault true;
          sandbox.githubFetchClient =
            pkgs.writers.writePython3Bin "gh"
              {
                libraries = [ pkgs.python3Packages.dbus-next ];
              }
              (
                builtins.replaceStrings [ "@GIT@" ] [ (lib.getExe pkgs.git) ] (
                  lib.readFile ./pineapplehunter/wrapper/github_fetch_client.py
                )
              );
        };

        systemd.user.services.pi-github-fetch = lib.mkIf enabled {
          Unit.Description = "Broker allowlisted GitHub reads for sandboxed Pi";
          Service = {
            Type = "dbus";
            BusName = busName;
            ExecStart = command;
            NoNewPrivileges = true;
            PrivateTmp = true;
          };
        };

        xdg.dataFile."dbus-1/services/${busName}.service" = lib.mkIf enabled {
          text = ''
            [D-BUS Service]
            Name=${busName}
            Exec=${command}
            SystemdService=pi-github-fetch.service
          '';
        };
      };
    };
}
