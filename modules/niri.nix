{
  flake.nixosModules.niri =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      config = {
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
        programs.niri.enable = lib.mkDefault true;
        security.pam.services.swaylock.text = config.security.pam.services.gdm-password.text;
      };
    };
}
