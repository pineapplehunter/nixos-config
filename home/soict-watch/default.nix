{
  flake.homeModules.soict-watch =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      python = pkgs.python3.withPackages (ps: [
        ps.pydantic
        ps.requests
      ]);
      discordIcon = "https://soict.org/wp-content/uploads/2026/05/cropped-2aOboQYrmw3L2D7MwM5SV5a0Byh9RCZwkrZANqIC-192x192.jpg";
      reportExtension = pkgs.writeText "soict-validate-report.ts" (
        builtins.replaceStrings
          [ "@REPORT_PYTHON@" "@REPORT_VALIDATOR@" ]
          [ "${python}/bin/python3" "${./.}/report.py" ]
          (builtins.readFile ./validate-report.ts)
      );
      monitor = pkgs.writeShellApplication {
        name = "soict-watch";
        runtimeInputs = [
          python
          pkgs.gitcrawl
          pkgs.git
          pkgs.local-notify
          config.programs.pi-coding-agent.package
        ];
        text = ''
          export SOICT_STATE_DIR=${lib.escapeShellArg "${config.xdg.stateHome}/soict-watch"}
          export SOICT_WEBHOOK_FILE=${lib.escapeShellArg config.sops.secrets.gitcrawl-slack-webhook.path}
          export SOICT_REPORT_EXTENSION=${reportExtension}
          export SOICT_DISCORD_ICON=${lib.escapeShellArg discordIcon}
          exec python3 ${./.}/monitor.py
        '';
      };
      notifyFailure = pkgs.writeShellApplication {
        name = "soict-watch-notify-failure";
        runtimeInputs = [ pkgs.local-notify ];
        text = ''
          stageFile=$1
          stage="不明（サービス起動時など）"
          # Ignore a marker left by an earlier invocation.
          if [[ -n "''${MONITOR_INVOCATION_ID:-}" && -r "$stageFile" ]] &&
              IFS= read -r marker < "$stageFile" &&
              [[ "$marker" == "$MONITOR_INVOCATION_ID:"* ]]; then
            case "''${marker#*:}" in
              setup) stage="初期化" ;;
              crawl) stage="ウェブサイト巡回" ;;
              compare) stage="スナップショット比較" ;;
              ai) stage="AIレビュー・報告書の検証" ;;
              discord) stage="Discordへの通知" ;;
              slack) stage="Slackへの投稿" ;;
              baseline) stage="比較基準の更新" ;;
            esac
          fi
          printf -v content "SOICTサイト監視に失敗しました。失敗箇所: %s。\n詳細: \`journalctl --user -u soict-watch.service -n 100\`\nPiログ: \`%s/<year>/pi.log\`\n次回の定期実行で再試行します。" \
            "$stage" ${lib.escapeShellArg "${config.xdg.stateHome}/soict-watch"}
          exec local-notify --username soict-watch --icon ${lib.escapeShellArg discordIcon} \
            --title 'SOICT monitor failed' --color '#ED4245' --content "$content"
        '';
      };
    in
    {
      # The encrypted value must be added to secrets/home.yaml before deployment.
      sops.secrets.gitcrawl-slack-webhook = { };

      home.packages = [ pkgs.gitcrawl ];

      systemd.user = {
        services = {
          soict-watch = {
            Unit = {
              Description = "Review current-year SOICT website changes with Pi and notify Slack in Japanese";
              Requires = [ "sops-nix.service" ];
              After = [ "sops-nix.service" ];
              OnFailure = [ "soict-watch-failure.service" ];
            };
            Service = {
              Type = "oneshot";
              ExecCondition = "${pkgs.python3}/bin/python3 -c 'import datetime, sys; sys.exit(datetime.date.today() > datetime.date(2026, 12, 10))'";
              ExecStart = lib.getExe monitor;
              TimeoutStartSec = "30min";
              RuntimeDirectory = "soict-watch";
              RuntimeDirectoryMode = "0700";
              RuntimeDirectoryPreserve = "yes";
              UMask = "0077";
            };
          };

          soict-watch-failure = {
            Unit.Description = "Notify Discord when the SOICT monitor fails";
            Service = {
              Type = "oneshot";
              ExecStart = "${lib.getExe notifyFailure} %t/soict-watch/stage";
              TimeoutStartSec = "30s";
            };
          };
        };

        timers.soict-watch = {
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
    };
}
