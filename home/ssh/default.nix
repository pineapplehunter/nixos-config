{ config, ... }:
{
  programs.ssh = {
    enable = true;
    matchBlocks = {
      linode = {
        hostname = "ihavenojob.work";
        user = "shogo";
        identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
      };
    };
  };
}
