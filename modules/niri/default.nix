{ pkgs, lib, ... }:
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
    security.pam.services.swaylock.text = ''
      auth include login
    '';
  };
}
