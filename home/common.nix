{ config, inputs, ... }:
let
  flake-config = config;
in
{
  flake.homeModules.common =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isLinux system;
      inherit (config.pineapplehunter) isNixos;
      pueueNotifyHook = pkgs.writeShellApplication {
        name = "pueue-notify-hook";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.local-notify
        ];
        text = lib.readFile ./pueue-notify-hook.sh;
      };
    in
    {
      imports =
        let
          mods = flake-config.flake.homeModules;
        in
        [
          mods.colored-man-pages
          mods.dconf
          mods.flatpak-update
          mods.ghostty
          mods.helix
          mods.julia
          mods.minimal
          mods.opencode
          mods.pi-coding-agent
          mods.packages
          mods.shell-config
          mods.ssh
          mods.zellij
          inputs.sops-nix.homeManagerModules.sops
          inputs.nix-index-database.homeModules.default
        ];

      programs = {
        bat = {
          enable = true;
          config = {
            theme = "ansi";
          };
          extraPackages = with pkgs.bat-extras; [
            batman
          ];
        };

        btop = {
          enable = true;
          settings = {
            graph_symbol = "block";
            cpu_single_graph = true;
          };
        };

        gnome-shell = {
          enable = isLinux && isNixos;
          extensions =
            let
              ge = pkgs.gnomeExtensions;
            in
            map (p: { package = p; }) [
              ge.appindicator
              ge.blur-my-shell
              ge.caffeine
              ge.gsconnect
              ge.night-theme-switcher
              ge.runcat
              ge.tailscale-qs
            ];
        };

        fd.enable = true;

        ripgrep.enable = true;

        fzf.enable = true;

        gpg.enable = true;

        julia = {
          enable = system == "x86_64-linux";
          package = pkgs.julia;
        };

        not-found-exec.enable = true;
        which-nix.enable = true;
        sudo-nix.enable = true;
        man-nix.enable = true;

        man = {
          enable = true;
          color.enable = true;
        };

        zsh = {
          plugins = [
            {
              name = "zsh-ssh";
              src = pkgs.fetchFromGitHub {
                owner = "sunlei";
                repo = "zsh-ssh";
                rev = "2049d186697f80386068b61732d785d40bf51213";
                hash = "sha256-YEgJzbanZ7iRD9hV8Pn6Ns3Vj87mKnwZjO0VIhamnX4=";
              };
            }
          ];
        };

        nix-index = {
          enable = true;
          enableBashIntegration = false;
          enableZshIntegration = false;
          enableFishIntegration = false;
        };
      };

      home = {
        packages = lib.optionals isLinux [ pkgs.local-notify ];

        shellAliases = {
          wget = "wget --hsts-file=${config.xdg.dataHome}";
        };

        sessionVariables = {
          CARGO_HOME = "${config.xdg.dataHome}/cargo";
        };
      };

      services = {
        flatpak-repo.enable = isLinux;
        flatpak-update.enable = isLinux;

        pueue = {
          enable = isLinux;
          settings = {
            daemon = {
              callback = lib.replaceString "\n" " " ''
                "${lib.getExe pueueNotifyHook}"
                --id "{{id}}"
                --command "{{command}}"
                --result "{{result}}"
                --exit-code "{{exit_code}}"
                --group "{{group}}"
                || true
              '';
              callback_log_lines = 10;
            };
          };
        };
      };

      systemd.user.services.local-notify = lib.mkIf isLinux {
        Unit.Description = "Send local notifications to Discord";
        Service = {
          Type = "dbus";
          BusName = "io.github.pineapplehunter.LocalNotify1";
          ExecStart = "${lib.getExe' pkgs.local-notify "local-notifyd"} --webhook-file ${config.sops.secrets.pueue-discord-webhook.path}";
        };
      };

      xdg = {
        enable = true;
        dataFile."dbus-1/services/io.github.pineapplehunter.LocalNotify1.service" = lib.mkIf isLinux {
          text = ''
            [D-BUS Service]
            Name=io.github.pineapplehunter.LocalNotify1
            Exec=${lib.getExe' pkgs.local-notify "local-notifyd"} --webhook-file ${config.sops.secrets.pueue-discord-webhook.path}
            SystemdService=local-notify.service
          '';
        };
        mimeApps.associations.added = {
          "x-scheme-handler/slack" = [ "com.slack.Slack.desktop" ];
          "x-scheme-handler/zoomus" = [ "us.zoom.Zoom.desktop" ];
          "x-scheme-handler/zoommtg" = [ "us.zoom.Zoom.desktop" ];
        };
      };

      sops = {
        age.sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
        defaultSopsFile = flake-config.sopsFile.home;
        secrets = {
          niks3-token.key = "niks-token";
          pueue-discord-webhook.key = "pueue-discord-webhook";
        };
      };
    };
}
