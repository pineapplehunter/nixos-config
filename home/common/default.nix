{
  pkgs,
  lib,
  config,
  self,
  ...
}:
let
  inherit (lib.attrsets) optionalAttrs;
  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
  inherit (config.pineapplehunter) is-nixos;

in
{
  imports =
    let
      inherit (self.homeModules)
        pineapplehunter
        flatpak-update
        helix-tree-sitter-module
        ;
    in
    [
      pineapplehunter
      flatpak-update
      helix-tree-sitter-module
    ];

  programs = {
    helix = {
      enable = true;
      defaultEditor = true;
      extraTreesitter = [
        {
          name = "kconfig";
          source = pkgs.fetchFromGitHub {
            owner = "tree-sitter-grammars";
            repo = "tree-sitter-kconfig";
            rev = "486fea71f61ad9f3fd4072a118402e97fe88d26c";
            hash = "sha256-a3uTjtA4KQ8KxEmpva2oHcqp8EwbI5+h9U+qoPSgDd4=";
          };
          comment-token = "#";
          file-types = [
            { glob = "Kconfig"; }
            { glob = "kconfig"; }
          ];
        }
        {
          name = "caddy";
          source = pkgs.fetchFromGitHub {
            owner = "Samonitari";
            repo = "tree-sitter-caddy";
            rev = "65b60437983933d00809c8927e7d8a29ca26dfa3";
            hash = "sha256-IDDz/2kC1Dslgrdv13q9NrCgrVvdzX1kQE6cld4+g2o=";
          };
          comment-token = "#";
          file-types = [
            { glob = "Caddyfile"; }
          ];
        }
        {
          name = "riscvasm";
          source = pkgs.fetchFromGitHub {
            owner = "erihsu";
            repo = "tree-sitter-riscvasm";
            rev = "01e82271a315d57be424392a3e46b2d929649a20";
            hash = "sha256-ZvOs0kAd6fqM+N8mmxBgKRlMrSRAXgy61Cwai6NQglU=";
          };
          comment-token = "#";
          file-types = [
            { glob = "Caddyfile"; }
          ];
        }
        {
          name = "linkerscript";
          source = pkgs.fetchFromGitHub {
            owner = "tree-sitter-grammars";
            repo = "tree-sitter-linkerscript";
            rev = "f99011a3554213b654985a4b0a65b3b032ec4621";
            hash = "sha256-Do8MIcl5DJo00V4wqIbdVC0to+2YYwfy08QWqSLMkQA=";
          };
          comment-token = "#";
          file-types = [
            { glob = "*.ld"; }
            { glob = "*.lds"; }
          ];
        }
        {
          name = "ninja";
          source = pkgs.fetchFromGitHub {
            owner = "alemuller";
            repo = "tree-sitter-ninja";
            rev = "0a95cfdc0745b6ae82f60d3a339b37f19b7b9267";
            hash = "sha256-e/LpQUL3UHHko4QvMeT40LCvPZRT7xTGZ9z1Zaboru4=";
          };
          comment-token = "#";
          file-types = [
            { glob = "*.ninja"; }
          ];
        }
      ];
      languages = import ./helix-languages.nix;
      settings = {
        theme = "github-light";
        editor = {
          lsp = {
            display-messages = true;
            display-inlay-hints = true;
          };
          auto-save = {
            focus-lost = true;
            after-delay.enable = true;
          };
          end-of-line-diagnostics = "hint";
          inline-diagnostics.cursor-line = "warning";
          file-picker.hidden = false;
          bufferline = "multiple";
          insert-final-newline = false;
        };
        keys.normal."C-g" = [
          ":write-all"
          ":new"
          ":insert-output lazygit"
          ":buffer-close!"
          ":redraw"
          ":reload-all"
        ];
      };
      themes = {
        github-light = builtins.fromTOML (builtins.readFile ./helix-github-light.toml);
      };
    };

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

    alacritty = {
      enable = isLinux;
      package =
        let
          inherit (pkgs) alacritty makeWrapper nixgl;
          inherit (lib) getExe;
        in
        pkgs.symlinkJoin {
          name = "alacritty-wrapped-${alacritty.version}";
          paths = [ alacritty ];
          nativeBuildInputs = [ makeWrapper ];
          postBuild =
            if is-nixos then
              ''
                rm $out/bin/alacritty
                makeWrapper "${getExe alacritty}" "$out/bin/alacritty" \
                  --set-default XCURSOR_THEME Adwaita \
                  --inherit-argv0
              ''
            else
              ''
                rm $out/bin/alacritty
                makeWrapper "${getExe (nixgl.override { enable32bits = false; }).nixGLMesa}" "$out/bin/alacritty" \
                  --set-default XCURSOR_THEME Adwaita \
                  --add-flags "${getExe alacritty}" \
                  --inherit-argv0
              '';
        };
      settings = import ./alacritty-config.nix;
    };

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
    packages =
      [
        pkgs.attic-client
        pkgs.chafa
        pkgs.difftastic
        pkgs.dust
        pkgs.elan
        pkgs.fd
        pkgs.ffmpegthumbnailer
        pkgs.file
        pkgs.fzf
        pkgs.htop
        pkgs.imagemagick
        pkgs.jq
        pkgs.ncdu
        pkgs.nix-index
        pkgs.nix-output-monitor
        pkgs.nix-search-cli
        pkgs.nix-tree
        pkgs.nix-update
        pkgs.nixfmt-rfc-style
        pkgs.nixpkgs-fmt
        pkgs.nixpkgs-review
        pkgs.npins
        pkgs.p7zip
        pkgs.ripgrep
        pkgs.starship
        pkgs.tokei
        pkgs.tree
        pkgs.typst
        pkgs.xh
        pkgs.zellij
        pkgs.zoxide

        # for editors
        pkgs.basedpyright
        pkgs.bash-language-server
        pkgs.buf
        pkgs.clang-tools
        pkgs.marksman
        pkgs.nixd
        pkgs.ruff
        pkgs.taplo
        pkgs.texlab
        pkgs.tinymist
        pkgs.vscode-langservers-extracted
        pkgs.nodePackages.typescript-language-server
      ]
      ++ lib.optionals isDarwin [ pkgs.iterm2 ]
      ++ lib.optionals isLinux [ pkgs.julia ];
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
