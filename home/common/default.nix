{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (lib.attrsets) optionalAttrs;
  inherit (pkgs.stdenv) isLinux;
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
      name = "${if package ? pname then package.pname else package.name}-wrapped";
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
in
{
  imports = [
    ../programs/kitty.nix
  ];

  programs = {
    helix = {
      enable = true;
      extraPackages = builtins.attrValues {
        inherit (pkgs)
          rust-analyzer
          bash-language-server
          nixd
          nixfmt-rfc-style
          clang-tools
          tinymist
          texlab
          marksman
          buf-language-server
          ruff
          ruff-lsp
          ;
        inherit (pkgs.nodePackages) typescript-language-server;
      };
      defaultEditor = true;
      languages = import ./helix-languages.nix { inherit kconfig-tree-sitter; };
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
      dotDir = ".config/zsh";
      autosuggestion.enable = true;
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
      enable = isLinux;
      extensions = map (p: { package = p; }) (
        builtins.attrValues {
          inherit (pkgs.gnomeExtensions)
            tailscale-status
            runcat
            caffeine
            appindicator
            just-perfection
            syncthing-indicator
            tiling-assistant
            night-theme-switcher
            blur-my-shell
            ;
        }
      );
    };

    yazi = {
      enable = true;
      package = wrapPackage {
        package = pkgs.yazi;
        programNames = [
          "yazi"
          "ya"
        ];
        PATH = builtins.attrValues {
          inherit (pkgs)
            ripgrep
            file
            ffmpegthumbnailer
            imagemagick
            fzf
            fd
            chafa
            zoxide
            p7zip
            jq
            ;
        };
      };
      keymap.manager.prepend_keymap = [
        {
          on = [
            "g"
            "e"
          ];
          run = "arrow 99999999";
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

    kitty' = {
      enable = true;
      package =
        let
          inherit (pkgs) kitty makeWrapper nixgl;
          inherit (lib) getExe;
        in
        pkgs.symlinkJoin {
          name = "kitty-wrapped";
          paths = [ kitty ];
          nativeBuildInputs = [ makeWrapper ];
          postBuild = ''
            rm $out/bin/kitty
            makeWrapper "${getExe (nixgl.override { enable32bits = false; }).nixGLMesa}" "$out/bin/kitty" \
              --add-flags "${getExe kitty}" \
              --inherit-argv0
          '';
        };
      theme = "CLRS";
      settings = {
        confirm_os_window_close = 0;
        font_family = "DejaVuSansM Nerd Font Mono";
        font_size = "10.0";
      };
    };

    fzf.enable = true;
  };

  home.packages = builtins.attrValues {
    inherit (pkgs)
      nixpkgs-review
      tokei
      htop
      nix-tree
      nixpkgs-fmt
      nixfmt-rfc-style
      nix-output-monitor
      difftastic
      starship
      zellij
      npins
      rustup
      elan
      ncdu
      nix-update
      ;
    julia = (if isLinux then pkgs.julia else pkgs.julia-bin);
    cachix-no-man = (
      pkgs.symlinkJoin {
        name = "cachix";
        version = pkgs.cachix.version;
        paths = [ pkgs.cachix.bin ];
      }
    );
    cachix-push = pkgs.writeShellScriptBin "cachix-push" ''
      SIZE=$(echo ''${2:-500M} | numfmt --from iec)
      CACHE=''${1:-pineapplehunter}
      nix path-info ./result -rS --json | jq "to_entries | sort_by(.value.closureSize) | .[] | select(.value.closureSize < $SIZE) | .key" -r | cachix push $CACHE
    '';
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

  home.shellAliases =
    {
      ls = "${pkgs.eza}/bin/eza --icons --git --time-style '+%y/%m/%d %H:%M'";
      la = "ls -a";
      ll = "ls -lha";
      wget = "wget --hsts-file=${config.xdg.dataHome}";
    }
    // optionalAttrs isLinux {
      ip = "ip -c";
    };

  home.sessionVariables = {
    RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
    CARGO_HOME = "${config.xdg.dataHome}/cargo";
    JULIA_DEPOT_PATH = "${config.xdg.dataHome}/julia:$JULIA_DEPOT_PATH";
  };

  services.syncthing.enable = pkgs.stdenv.isLinux;

  home.stateVersion = config.home.version.release;
  programs.home-manager.enable = true;
  news.display = "silent";
}
