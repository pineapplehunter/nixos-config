{ pkgs, lib, ... }:
{
  config = {
    environment.systemPackages = with pkgs; [
      fuzzel
      xwayland-satellite
      waybar
      pavucontrol
      mako
      swaylock
      swayidle
    ];
    programs.niri.enable = lib.mkDefault true;
    security.pam.services.swaylock.text = ''
      auth include login
    '';
  };
}
