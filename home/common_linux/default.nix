{ pkgs, ... }:
{
  programs = {
    gnome-shell = {
      enable = true;
      extensions = map (p: { package = p; }) (with pkgs.gnomeExtensions; [
        tailscale-status
        runcat
        caffeine
        appindicator
        just-perfection
        syncthing-indicator
        tiling-assistant
      ]);
    };
  };

  services.syncthing.enable = true;

  home.shellAliases = {
    ip = "ip -c";
  };
}
