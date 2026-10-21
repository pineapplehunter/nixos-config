{
  flake.homeModules.soict-watch =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      monitor = pkgs.writeShellApplication {
        name = "soict-watch";
        runtimeInputs = [
          pkgs.python3
          pkgs.gitcrawl
          pkgs.git
          config.programs.pi-coding-agent.package
        ];
        text = ''
          export SOICT_STATE_DIR=${lib.escapeShellArg "${config.xdg.stateHome}/soict-watch"}
          export SOICT_WEBHOOK_FILE=${lib.escapeShellArg config.sops.secrets.gitcrawl-slack-webhook.path}
          exec python3 ${./monitor.py}
        '';
      };
    in
    {
      # The encrypted value must be added to secrets/home.yaml before deployment.
      sops.secrets.gitcrawl-slack-webhook = { };

      home.packages = [ pkgs.gitcrawl ];

      systemd.user.services.soict-watch = {
        Unit = {
          Description = "Review current-year SOICT website changes with Pi and notify Slack in Japanese";
          Requires = [ "sops-nix.service" ];
          After = [ "sops-nix.service" ];
        };
        Service = {
          Type = "oneshot";
          ExecCondition = "${pkgs.python3}/bin/python3 -c 'import datetime, sys; sys.exit(datetime.date.today() > datetime.date(2026, 12, 10))'";
          ExecStart = lib.getExe monitor;
          TimeoutStartSec = "30min";
          UMask = "0077";
        };
      };

      systemd.user.timers.soict-watch = {
        Unit.Description = "Check the SOICT website at 09:00, 12:00, and 16:00";
        Timer = {
          OnCalendar = [
            "2026-01..11-* 09,12,16:00:00"
            "2026-12-01..10 09,12,16:00:00"
          ];
          Persistent = true;
          AccuracySec = "1s";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
}
