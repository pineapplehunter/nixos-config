{ config, pkgs, ... }:
{
  home.packages = with pkgs;[
    julia-bin
  ];

  home.file.".julia/config/startup.jl".text = ''
    try
      using OhMyREPL
    catch e
      @warn e
    end
  '';

  home.shellAliases = {
    ls = "${pkgs.eza}/bin/eza --icons --git --time-style '+%y/%m/%d %H:%M'";
    la = "ls -a";
    ll = "ls -lha";
  };

  home.stateVersion = config.home.version.release;
  programs.home-manager.enable = true;
}
