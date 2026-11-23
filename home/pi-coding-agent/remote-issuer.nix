{ flake.homeModules.pi-coding-agent = { pkgs, lib, ... }:
  let
    python = pkgs.python3.withPackages (p: [ p.cryptography p.dbus-next ]);
    issuer = pkgs.writeShellApplication {
      name = "pi-remote-issue-certificate";
      runtimeInputs = [ python ];
      text = ''exec ${python}/bin/python3 ${./pineapplehunter/wrapper/pi_remote_issuer.py} "$@"'';
    };
  in {
    options.programs.pi-coding-agent.sandbox.remoteIssuerClient = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "Pi Remote certificate issuer client exposed inside the sandbox.";
    };
    config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      programs.pi-coding-agent.sandbox.remoteIssuerClient = issuer;
      home.packages = [ issuer ];
      systemd.user.services.pi-remote-issuer = {
        Unit.Description = "Pi Remote client certificate issuer";
        Service = {
          Type = "dbus";
          BusName = "io.github.pineapplehunter.PiRemoteCA1";
          ExecStart = "${issuer}/bin/pi-remote-issue-certificate --dbus";
          NoNewPrivileges = true;
          PrivateTmp = true;
        };
      };
      xdg.dataFile."dbus-1/services/io.github.pineapplehunter.PiRemoteCA1.service".text = ''
        [D-BUS Service]
        Name=io.github.pineapplehunter.PiRemoteCA1
        Exec=${issuer}/bin/pi-remote-issue-certificate --dbus
        SystemdService=pi-remote-issuer.service
      '';
    };
  };
}
