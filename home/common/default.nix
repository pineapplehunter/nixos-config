{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (lib.attrsets) optionalAttrs;
  inherit (pkgs.stdenv) isLinux;
in
{
  programs = {
    helix = {
      enable = true;
      package =
        let
          inherit (pkgs) helix makeWrapper;
          binPath = builtins.attrValues {
            inherit (pkgs)
              rust-analyzer
              bash-language-server
              nixd
              nixfmt-rfc-style
              clang-tools
              tinymist
              texlab
              marksman
              ;
            inherit (pkgs.nodePackages) typescript-language-server;
            python-env = pkgs.python3.withPackages (
              ps:
              builtins.attrValues {
                inherit (ps) python-lsp-server;
              }
            );
          };
        in
        pkgs.symlinkJoin {
          name = "helix-wrapped";
          paths = [ helix ];
          nativeBuildInputs = [ makeWrapper ];
          postBuild = ''
            wrapProgram "$out/bin/hx" \
              --suffix PATH : "${lib.makeBinPath binPath}"
          '';
        };
      defaultEditor = true;
      languages = import ./helix-languages.nix {
        inherit lib;
        inherit (pkgs) nixd;
      };
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
            makeWrapper "${getExe nixgl.nixGLMesa}" "$out/bin/alacritty" \
              --set-default XCURSOR_THEME Adwaita \
              --add-flags "${getExe alacritty}" \
              --inherit-argv0
          '';
        };
      settings = import ./alacritty-config.nix;
    };

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
        with pkgs.gnomeExtensions;
        [
          tailscale-status
          runcat
          caffeine
          appindicator
          just-perfection
          syncthing-indicator
          tiling-assistant
          night-theme-switcher
        ]
      );
    };

    yazi.enable = true;

    gh.enable = true;

    fd.enable = true;

    ripgrep.enable = true;
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
      ;
    julia = (if isLinux then pkgs.julia else pkgs.julia-bin);
    cachix-no-man = (
      pkgs.symlinkJoin {
        name = "cachix";
        version = pkgs.cachix.version;
        paths = [ pkgs.cachix.bin ];
      }
    );
  };

  home.file.".julia/config/startup.jl".text = ''
    try
      using OhMyREPL
    catch e
      @warn e
    end
  '';

  home.shellAliases =
    {
      ls = "${pkgs.eza}/bin/eza --icons --git --time-style '+%y/%m/%d %H:%M'";
      la = "ls -a";
      ll = "ls -lha";
    }
    // optionalAttrs isLinux {
      ip = "ip -c";
    };

  services.syncthing.enable = pkgs.stdenv.isLinux;

  home.stateVersion = config.home.version.release;
  programs.home-manager.enable = true;
  news.display = "silent";
}
