{
  pkgs,
  config,
  self,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  inherit (config.pineapplehunter) isNixos;
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
        julia
        minimal
        pineapplehunter
        ssh
        zellij
        ;
    in
    [
      alacritty
      dconf
      flatpak-update
      ghostty
      helix
      julia
      minimal
      pineapplehunter
      ssh
      zellij
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

  };

  home = {
    shellAliases = {
      wget = "wget --hsts-file=${config.xdg.dataHome}";
    };

    sessionVariables = {
      CARGO_HOME = "${config.xdg.dataHome}/cargo";
    };
  };

  services.flatpak-repo.enable = isLinux;
  services.flatpak-update.enable = isLinux;
}
