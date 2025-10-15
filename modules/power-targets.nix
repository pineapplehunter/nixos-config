{
  flake.nixosModules.power-targets = {
    systemd = {
      targets = {
        power-ac.description = "Powered by AC";
        power-battery.description = "Powered by Battery";
      };

      services = {
        update-power-target = {
          script = ''
            POWER_ONLINE=$(cat /sys/class/power_supply/AC/online)
            if [[ "$POWER_ONLINE" == "1" ]]; then
              systemctl stop power-battery.target
              systemctl start power-ac.target
            else
              systemctl stop power-ac.target
              systemctl start power-battery.target
            fi
          '';
          wantedBy = [ "default.target" ];
        };
        update-power-target-after-resume = {
          script = ''
            systemctl start update-power-target.service
          '';
          wantedBy = [ "suspend.target" ];
          after = [ "suspend.target" ];
        };
      };
    };

    services.udev.extraRules = ''
      # Update power target on power state change
      SUBSYSTEM=="power_supply", ENV{POWER_SUPPLY_NAME}=="AC", TAG+="systemd", ENV{SYSTEMD_WANTS}="update-power-target.service"
    '';
  };
}
