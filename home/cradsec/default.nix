{ config, ... }:
{
  programs.ssh = {
    enable = true;
    matchBlocks = {
      cradsec = {
        hostname = "10.102.51.25";
        user = "takata";
        identityFile = "${config.home.homeDirectory}/.ssh/cradsec_takata";
      };
    };
  };
}
