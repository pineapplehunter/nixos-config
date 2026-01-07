{
  flake.homeModules.julia =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.programs.julia;
    in
    {
      options.programs.julia = {
        enable = lib.mkEnableOption "julia";
        package = lib.mkPackageOption pkgs "julia" { };
      };
      config = lib.mkIf cfg.enable {
        xdg.dataFile."julia/config/startup.jl".text = ''
          try
            using OhMyREPL
          catch e
            @warn e
          end
        '';

        home.sessionVariables.JULIA_DEPOT_PATH = "${config.xdg.dataHome}/julia:$JULIA_DEPOT_PATH";

        # use julia-bin because julia fails to build
        # https://github.com/NixOS/nixpkgs/issues/475534
        home.packages = [ cfg.package ];

        # precompile julia
        systemd.user = {
          services = {
            julia-precompile = {
              Unit.Description = "Precompile julia packages for fast repl";
              Service = {
                ExecStart = pkgs.writeShellScript "julia-precompile" ''
                  julia ${pkgs.writeText "julia-precompile.jl" ''
                    using Pkg
                    ["OhMyREPL", "Unitful", "UnitfulData"] .|> Pkg.add
                    Pkg.precompile()
                  ''}
                '';
                Environment = [
                  "JULIA_DEPOT_PATH=${config.home.sessionVariables.JULIA_DEPOT_PATH}"
                  "PATH=${lib.makeBinPath [ cfg.package ]}"
                ];
              };
              Install.WantedBy = [ "default.target" ];
            };
            julia-update = {
              Unit.Description = "Update julia packages";
              Service = {
                ExecStart = pkgs.writeShellScript "julia-update" ''
                  julia ${pkgs.writeText "julia-update.jl" ''
                    using Pkg
                    Pkg.update()
                  ''}
                '';
                Environment = [
                  "JULIA_DEPOT_PATH=${config.home.sessionVariables.JULIA_DEPOT_PATH}"
                  "PATH=${lib.makeBinPath [ cfg.package ]}"
                ];
              };
            };
          };
          timers = {
            julia-update = {
              Unit.Description = "Update julia package";
              Timer.OnCalendar = "weekly";
              Install.WantedBy = [ "timers.target" ];
            };
          };
        };
      };
    };
}
