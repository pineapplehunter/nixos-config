{
  flake.nixosModules.power-targets =
    { config, ... }:
    {
      systemd.targets = {
        power-ac.description = "Powered by AC";
        power-battery.description = "Powered by Battery";
      };

      services.udev.extraRules = ''
        # When AC adapter is plugged in
        SUBSYSTEM=="power_supply", ENV{POWER_SUPPLY_ONLINE}=="1", ENV{POWER_SUPPLY_NAME}=="AC", \
          RUN+="${config.systemd.package}/bin/systemctl --no-block start power-ac.target"
        SUBSYSTEM=="power_supply", ENV{POWER_SUPPLY_ONLINE}=="1", ENV{POWER_SUPPLY_NAME}=="AC", \
          RUN+="${config.systemd.package}/bin/systemctl --no-block stop power-battery.target"

        # When AC adapter is unplugged
        SUBSYSTEM=="power_supply", ENV{POWER_SUPPLY_ONLINE}=="0", ENV{POWER_SUPPLY_NAME}=="AC", \
          RUN+="${config.systemd.package}/bin/systemctl --no-block stop power-ac.target"
        SUBSYSTEM=="power_supply", ENV{POWER_SUPPLY_ONLINE}=="0", ENV{POWER_SUPPLY_NAME}=="AC", \
          RUN+="${config.systemd.package}/bin/systemctl --no-block start power-battery.target"
      '';
    };
}
