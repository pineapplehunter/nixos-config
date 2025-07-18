{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) optionalAttrs;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  imports = [ ./packages.nix ];

  config = {
    programs = {
      starship.enable = true;

      bash.enable = true;

      zsh = {
        enable = true;
        dotDir = ".config/zsh";
        history = {
          append = true;
          ignoreAllDups = true;
          ignoreDups = true;
          ignoreSpace = true;
          path = "${config.xdg.cacheHome}/zsh/zsh_history";
        };
      };

      direnv = {
        enable = true;
        nix-direnv.enable = true;
        config = {
          warn_timeout = "1h";
        };
        silent = true;
      };

      yazi = {
        enable = true;
        keymap.mgr.prepend_keymap = [
          {
            on = [
              "g"
              "e"
            ];
            run = "arrow bot";
            desc = "Move cursor to the bottom";
          }
        ];
        settings.mgr.ratio = [
          1
          2
          3
        ];
      };

      gh.enable = true;

      git = {
        enable = true;
        signing = {
          signByDefault = true;
          key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
          format = "ssh";
        };
        aliases =
          let
            difft = lib.getExe pkgs.difftastic;
          in
          {
            pushf = "push --force-with-lease";
            dlog = "-c diff.external=${difft} log --ext-diff";
            dshow = "-c diff.external=${difft} show --ext-diff";
            ddiff = "-c diff.external=${difft} diff";
          };
        extraConfig = {
          branch.sort = "-committerdate";
          column.ui = "auto";
          fetch.writeCommitGraph = true;
          init.defaultBranch = "main";
          rerere.enabled = true;
        };
      };

      home-manager = {
        enable = true;
        path = lib.mkForce null;
      };

      lazygit = {
        enable = true;
        settings = {
          git.overrideGpg = true;
        };
      };
    };
    home.shellAliases = lib.mkMerge [
      {
        ls = "${pkgs.eza}/bin/eza --icons --git --time-style '+%y/%m/%d %H:%M'";
        la = "ls -a";
        ll = "ls -lha";
      }
      (optionalAttrs isLinux {
        ip = "ip -c";
      })
    ];

    home.stateVersion = config.home.version.release;
    news.display = "silent";
  };
}
