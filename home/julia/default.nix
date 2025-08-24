{
  pkgs,
  config,
  lib,
  ...
}:

{
  config = lib.mkIf pkgs.hostPlatform.isLinux {
    xdg.dataFile."julia/config/startup.jl".text = ''
      try
        using OhMyREPL
      catch e
        @warn e
      end
    '';

    home.sessionVariables.JULIA_DEPOT_PATH = "${config.xdg.dataHome}/julia:$JULIA_DEPOT_PATH";

    home.packages = with pkgs; [ julia ];

    # precompile julia
    systemd.user.services.julia-precompile = {
      Unit.Description = "Precompile julia packages for fast repl";
      Service = {
        ExecStart = pkgs.writeShellScript "julia-precompile" ''
          julia ${pkgs.writeText "julia-precompile.jl" ''
            using Pkg
            Pkg.precompile()
          ''}
        '';
        Environment = [
          "JULIA_DEPOT_PATH=${config.home.sessionVariables.JULIA_DEPOT_PATH}"
          "PATH=${lib.makeBinPath [ pkgs.julia ]}"
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
