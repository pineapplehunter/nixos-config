{
  flake.nixosModules.hibernate =
    { lib, config, ... }:
    let
      cfg = config.systemd.hibernation;
    in
    {
      options.systemd.hibernation = {
        enable = lib.mkEnableOption "hibernation";
        delaySec = lib.mkOption {
          description = "Time to suspend until hibernation";
          type = lib.types.str;
          default = "12h";
        };
      };

      config = lib.mkIf cfg.enable {
        services.logind.settings.Login = {
          HandleLidSwitch = "suspend-then-hibernate";
          HandleLidSwitchDocked = "suspend-then-hibernate";
          HandleLidSwitchExternalPower = "suspend-then-hibernate";
        };
        systemd.sleep.extraConfig = ''
          HibernateDelaySec=${cfg.delaySec}
        '';
      };
    };
}
