{ config, pkgs, ... }:
{
  programs = {
    gnome-shell = {
      enable = true;
      extensions = map (p: { package = p; }) (with pkgs.gnomeExtensions; [
        tailscale-status
        runcat
        caffeine
        appindicator
        just-perfection
        syncthing-indicator
        tiling-assistant
      ]);
    };
  };

  services.syncthing.enable = true;

  home.packages = with pkgs;[
    julia
  ];

  home.file.".julia/config/startup.jl".text = ''
    try
      using OhMyREPL
    catch e
      @warn e
    end
  '';

  home.shellAliases = {
    ip = "ip -c";
    ls = "${pkgs.eza}/bin/eza --icons --git --time-style '+%y/%m/%d %H:%M'";
    la = "ls -a";
    ll = "ls -lha";
  };

  home.stateVersion = config.home.version.release;
  programs.home-manager.enable = true;
}
