{ flake.homeModules.pi-coding-agent = { pkgs, lib, ... }:
  let
    bus = "io.github.pineapplehunter.PiRemoteTicket1";
    python = pkgs.python3.withPackages (p: [ p.dbus-next ]);
    client = pkgs.writeShellApplication {
      name = "pi-remote-request-ticket";
      runtimeInputs = [ pkgs.openssh ];
      text = ''exec ${python}/bin/python3 -I ${./pineapplehunter/wrapper/pi_remote_ticket.py} "$@"'';
    };
    daemon = "${client}/bin/pi-remote-request-ticket --dbus";
  in {
    options.programs.pi-coding-agent.sandbox.remoteTicketClient = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "Pi Remote ticket request client exposed inside the sandbox.";
    };
    config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      programs.pi-coding-agent.sandbox.remoteTicketClient = client;
      home.packages = [ client ];
      systemd.user.services.pi-remote-ticket = {
        Unit.Description = "Pi Remote host ticket broker";
        Service = {
          Type = "dbus";
          BusName = bus;
          ExecStart = daemon;
          NoNewPrivileges = true;
          PrivateTmp = true;
        };
      };
      xdg.dataFile."dbus-1/services/${bus}.service".text = ''
        [D-BUS Service]
        Name=${bus}
        Exec=${daemon}
        SystemdService=pi-remote-ticket.service
      '';
    };
  };
}
