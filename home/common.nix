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
                "${lib.getExe pkgs.pueue-discord-notify}"
                --webhook-file "${config.sops.secrets.pueue-discord-webhook.path}"
                --id "{{id}}"
                --command "{{command}}"
                --result "{{result}}"
                --exit-code "{{exit_code}}"
                --group "{{group}}"
              '';
              callback_log_lines = 10;
            };
          };
        };
      };

      xdg = {
        enable = true;
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
