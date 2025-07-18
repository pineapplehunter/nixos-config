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
        alacritty
        dconf
        flatpak-update
        ghostty
        helix
        pineapplehunter
        zellij
        minimal
        ;
    in
    [
      alacritty
      dconf
      flatpak-update
      ghostty
      helix
      pineapplehunter
      zellij
      minimal
      ./packages.nix
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

    fish.enable = true;

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

    fd.enable = true;

    ripgrep.enable = true;

    fzf.enable = true;

    gpg.enable = true;

  };

  xdg.dataFile."julia/config/startup.jl".text = ''
    try
      using OhMyREPL
    catch e
      @warn e
    end
  '';

  home = {
    shellAliases = {
      wget = "wget --hsts-file=${config.xdg.dataHome}";
    };

    sessionVariables = {
      CARGO_HOME = "${config.xdg.dataHome}/cargo";
      JULIA_DEPOT_PATH = "${config.xdg.dataHome}/julia:$JULIA_DEPOT_PATH";
    };
  };

  services.flatpak-update.enable = isLinux && !is-nixos;
}
