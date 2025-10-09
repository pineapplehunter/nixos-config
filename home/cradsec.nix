{
  flake.homeModules.cradsec =
    { config, ... }:
    {
      programs.ssh = {
        enable = true;
        matchBlocks = {
          cradsec-sgx = {
            hostname = "10.102.51.25";
            user = "takata";
            identityFile = "${config.home.homeDirectory}/.ssh/cradsec_takata";
          };
          cradsec-tdx = {
            hostname = "10.102.51.31";
            user = "takata";
            identityFile = "${config.home.homeDirectory}/.ssh/cradsec_takata";
          };
        };
      };
    };
}
