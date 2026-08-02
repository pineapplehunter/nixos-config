{
  flake.nixosModules.prometheus-smartctl =
    { config, lib, ... }:
    let
      cfg = config.my.prometheus-smartctl;
    in
    {
      options.my.prometheus-smartctl.enable = lib.mkEnableOption "Prometheus smartctl exporter";

      config = lib.mkIf cfg.enable {
        services.prometheus.exporters.smartctl.enable = true;
        networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
          config.services.prometheus.exporters.smartctl.port
        ];
      };
    };
}
