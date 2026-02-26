{
  flake.homeModules.ssh =
    { config, ... }:
    {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        matchBlocks = {
          linode = {
            hostname = "ihavenojob.work";
            user = "shogo";
            identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
            port = 13428;
          };
          "*" = {
            compression = true;
          };
        };
      };
    };
}
