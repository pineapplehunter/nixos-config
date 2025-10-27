{ config, ... }:
let
  flake-config = config;
in
{
  flake.homeModules.common =
    { pkgs, config, ... }:
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
          mods.alacritty
          mods.dconf
          mods.flatpak-update
          mods.ghostty
          mods.helix
          mods.inkscape-symbols
          mods.julia
          mods.minimal
          mods.ssh
          mods.zellij
          mods.packages
        ];

      programs = {
        bat = {
          enable = true;
          config = {
            theme = "GitHub";
          };
        };

        btop = {
          enable = true;
          settings = {
            graph_symbol = "block";
            cpu_single_graph = true;
          };
        };

        zsh = {
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
          historySubstringSearch = {
            enable = true;
            searchUpKey = "$terminfo[kcuu1]";
            searchDownKey = "$terminfo[kcud1]";
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
              ge.just-perfection
              ge.night-theme-switcher
              ge.quick-lang-switch
              ge.runcat
              ge.tailscale-qs
              ge.tiling-assistant
            ];
        };

        fd.enable = true;

        ripgrep.enable = true;

        fzf.enable = true;

        gpg.enable = true;

        julia.enable = system == "x86_64-linux";
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
        pueue.enable = isLinux;
      };

      xdg = {
        enable = true;
        mimeApps.associations.added = {
          "x-scheme-handler/slack" = [ "com.slack.Slack.desktop" ];
          "x-scheme-handler/zoomus" = [ "us.zoom.Zoom.desktop" ];
          "x-scheme-handler/zoommtg" = [ "us.zoom.Zoom.desktop" ];
        };
      };
    };
}
