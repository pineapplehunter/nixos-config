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
  wrapPackage =
    {
      package,
      programNames ? [ package.pname ],
      PATH ? null,
    }:
    let
      binPath = lib.optionalString (PATH != null) lib.makeBinPath PATH;
    in
    pkgs.symlinkJoin {
      name = "${package.pname or package.name}-wrapped";
      paths = [ package ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = lib.strings.concatStrings (
        map (p: ''
          wrapProgram "$out/bin/${p}" \
            --suffix PATH : "${binPath}"
        '') programNames
      );
    };

  kconfig-tree-sitter = pkgs.fetchFromGitHub {
    owner = "tree-sitter-grammars";
    repo = "tree-sitter-kconfig";
    rev = "486fea71f61ad9f3fd4072a118402e97fe88d26c";
    hash = "sha256-a3uTjtA4KQ8KxEmpva2oHcqp8EwbI5+h9U+qoPSgDd4=";
  };
  caddy-tree-sitter = pkgs.fetchFromGitHub {
    owner = "Samonitari";
    repo = "tree-sitter-caddy";
    rev = "65b60437983933d00809c8927e7d8a29ca26dfa3";
    hash = "sha256-IDDz/2kC1Dslgrdv13q9NrCgrVvdzX1kQE6cld4+g2o=";
  };
in
{
  imports =
    let
      inherit (self.homeModules) pineapplehunter flatpak-update;
    in
    [
      pineapplehunter
      flatpak-update
    ];

  programs = {
    helix = {
      enable = true;
      defaultEditor = true;
      languages = import ./helix-languages.nix { inherit kconfig-tree-sitter caddy-tree-sitter; };
      settings = {
        theme = "github-light";
        editor = {
          # line-number = "relative";
          lsp = {
            display-messages = true;
            display-inlay-hints = true;
          };
          auto-save = {
            focus-lost = true;
            after-delay.enable = true;
          };
          end-of-line-diagnostics = "hint";
          inline-diagnostics.cursor-line = "error";
        };
        # keys = {
        #   normal.esc = [ "collapse_selection" ":w" ];
        #   select.esc = [ "collapse_selection" "normal_mode" ":w" ];
        #   insert.esc = [ "normal_mode" ":w" ];
        # };
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
          ge.just-perfection
          ge.night-theme-switcher
          ge.runcat
          ge.syncthing-indicator
          ge.tailscale-status
          ge.tiling-assistant
        ];
    };

    yazi = {
      enable = true;
      package = wrapPackage {
        package = pkgs.yazi;
        programNames = [
          "yazi"
          "ya"
        ];
        PATH = [
          pkgs.chafa
          pkgs.fd
          pkgs.ffmpegthumbnailer
          pkgs.file
          pkgs.fzf
          pkgs.imagemagick
          pkgs.jq
          pkgs.p7zip
          pkgs.ripgrep
          pkgs.zoxide
        ];
      };
      keymap.manager.prepend_keymap = [
        {
          on = [
            "g"
            "e"
          ];
          run = "arrow bot";
          desc = "Move cursor to the bottom";
        }
      ];
      settings.manager.ratio = [
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
          name = "alacritty-wrapped";
          paths = [ alacritty ];
          nativeBuildInputs = [ makeWrapper ];
          postBuild = ''
            rm $out/bin/alacritty
            makeWrapper "${getExe (nixgl.override { enable32bits = false; }).nixGLMesa}" "$out/bin/alacritty" \
              --set-default XCURSOR_THEME Adwaita \
              --add-flags "${getExe alacritty}" \
              --inherit-argv0
          '';
        };
      settings = import ./alacritty-config.nix;
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
  };

  xdg.dataFile."julia/config/startup.jl".text = ''
    try
      using OhMyREPL
    catch e
      @warn e
    end
  '';

  xdg.configFile."helix/runtime/queries/kconfig".source = pkgs.runCommand "kconfig-query" { } ''
    ln -s ${kconfig-tree-sitter}/queries $out
  '';

  home = {
    packages =
      let
        cachix-no-man = pkgs.symlinkJoin {
          inherit (pkgs.cachix) version;
          name = "cachix";
          paths = [ pkgs.cachix.bin ];
        };
        cachix-push = pkgs.writeShellScriptBin "cachix-push" ''
          SIZE=$(echo ''${2:-500M} | numfmt --from iec)
          CACHE=''${1:-pineapplehunter}
          nix path-info ./result -rS --json \
            | ${pkgs.jq}/bin/jq "to_entries | sort_by(.value.closureSize) | .[] | select(.value.closureSize < $SIZE) | .key" -r \
            | ${pkgs.cachix.bin}/bin/cachix push $CACHE
        '';
      in
      [
        pkgs.attic-client
        pkgs.difftastic
        pkgs.dust
        pkgs.elan
        pkgs.htop
        pkgs.lazygit
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
        pkgs.rustup
        pkgs.starship
        pkgs.tokei
        pkgs.tree
        pkgs.typst
        pkgs.zellij

        cachix-no-man
        cachix-push

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
      RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
      CARGO_HOME = "${config.xdg.dataHome}/cargo";
      JULIA_DEPOT_PATH = "${config.xdg.dataHome}/julia:$JULIA_DEPOT_PATH";
    };
  };

  services = {
    syncthing.enable = isLinux;
    flatpak-update.enable = isLinux && !is-nixos;
  };

  home.stateVersion = config.home.version.release;
  news.display = "silent";
}
