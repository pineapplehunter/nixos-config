{
  pkgs,
  lib,
  config,
  self,
  ...
}:
let
  inherit (lib.attrsets) optionalAttrs;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  inherit (config.pineapplehunter) is-nixos;
in
{
  imports =
    let
      inherit (self.homeModules)
        pineapplehunter
        flatpak-update
        helix
        alacritty
        ;
    in
    [
      pineapplehunter
      flatpak-update
      helix
      alacritty
      ./packages.nix
    ];

  programs = {
    zellij = {
      enable = true;
      settings = import ./zellij-config.nix;
      # disable auto startup
      enableZshIntegration = false;
      enableFishIntegration = false;
      enableBashIntegration = false;
    };

    bat = {
      enable = true;
      config = {
        theme = "GitHub";
      };
    };

    starship.enable = true;

    btop = {
      enable = true;
      settings = {
        graph_symbol = "block";
        cpu_single_graph = true;
      };
    };

    bash.enable = true;

    zsh = {
      enable = true;
      autosuggestion.enable = true;
      dotDir = ".config/zsh";
      syntaxHighlighting.enable = true;
      history = {
        append = true;
        ignoreAllDups = true;
        ignoreDups = true;
        ignoreSpace = true;
        path = "${config.xdg.cacheHome}/zsh/zsh_history";
      };
      historySubstringSearch = {
        enable = true;
        searchUpKey = "$terminfo[kcuu1]";
        searchDownKey = "$terminfo[kcud1]";
      };
    };

    fish.enable = true;

    direnv = {
      enable = true;
      nix-direnv.enable = true;
      config = {
        warn_timeout = "1h";
      };
      silent = true;
    };

    gnome-shell = {
      enable = isLinux && is-nixos;
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
          ge.tailscale-status
          ge.tiling-assistant
        ];
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

    fd.enable = true;

    ripgrep.enable = true;

    ghostty = {
      enable = isLinux;
      package =
        if is-nixos then
          pkgs.ghostty
        else
          let
            inherit (lib) getExe;
            inherit (pkgs) ghostty makeWrapper nixgl;
          in
          pkgs.symlinkJoin {
            name = "ghostty-wrapped-${ghostty.version}";
            paths = [ ghostty ];
            nativeBuildInputs = [ makeWrapper ];
            meta.mainProgram = "ghostty";
            postBuild = ''
              rm $out/bin/ghostty
              makeWrapper "${getExe (nixgl.override { enable32bits = false; }).nixGLMesa}" "$out/bin/ghostty" \
                --add-flags "${getExe ghostty}" \
            '';
          };
      settings = {
        theme = "Adwaita";
        window-theme = "light";
        font-size = 10;
        gtk-titlebar = false;
        keybind = [
          "ctrl+shift+plus=increase_font_size:1"
          "ctrl+shift+equal=decrease_font_size:1"
          "ctrl+shift+0=reset_font_size"
          "ctrl+enter=unbind"
        ];
      };
    };

    fzf.enable = true;

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

    gpg.enable = true;

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

  xdg.dataFile."julia/config/startup.jl".text = ''
    try
      using OhMyREPL
    catch e
      @warn e
    end
  '';

  dconf.settings = {
    "org/gnome/desktop/applications/terminal" = {
      exec = "ghostty";
      exec-arg = "";
    };
    "org/gnome/desktop/wm/keybindings" = {
      close = [ "<Shift><Super>q" ];
    };
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "Terminal";
      command = "ghostty";
      binding = "<Super>Return";
    };
    "com/github/stunkymonkey/nautilus-open-any-terminal" = {
      terminal = "ghostty";
      lockAll = true;
    };
  };

  home = {
    shellAliases = lib.mkMerge [
      {
        ls = "${pkgs.eza}/bin/eza --icons --git --time-style '+%y/%m/%d %H:%M'";
        la = "ls -a";
        ll = "ls -lha";
        wget = "wget --hsts-file=${config.xdg.dataHome}";
      }
      (optionalAttrs isLinux {
        ip = "ip -c";
      })
    ];

    sessionVariables = {
      CARGO_HOME = "${config.xdg.dataHome}/cargo";
      JULIA_DEPOT_PATH = "${config.xdg.dataHome}/julia:$JULIA_DEPOT_PATH";
    };
  };

  services.flatpak-update.enable = isLinux && !is-nixos;

  home.stateVersion = config.home.version.release;
  news.display = "silent";
}
