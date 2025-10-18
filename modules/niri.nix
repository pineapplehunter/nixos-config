{
  flake.nixosModules.niri =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      config = lib.mkIf config.programs.niri.enable {
        # opinionated packages needed to run niri
        environment.systemPackages = with pkgs; [
          brightnessctl
          fuzzel
          mako
          pavucontrol
          swayidle
          swaylock
          waybar
          xwayland-satellite
        ];
        security.pam.services.swaylock.text = config.security.pam.services.gdm-password.text;
      };
    };
}
