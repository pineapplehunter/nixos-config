{ config, ... }:
{
  programs.ssh = {
    enable = true;
    matchBlocks = {
      kpro-njlab = {
        hostname = "kpro-njlab";
        user = "takata";
        identityFile = "${config.home.homeDirectory}/.ssh/cradsec_takata";
      };
    };
  };
}
