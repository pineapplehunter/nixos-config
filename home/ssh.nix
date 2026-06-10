{
  flake.homeModules.ssh =
    { config, ... }:
    {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings = {
          linode = {
            hostname = "ihavenojob.work";
            user = "shogo";
            identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
            port = 13428;
          };

          # tailscale hosts
          beast = {
            hostname = "beast";
            user = "shogo";
          };
          daniel-njlab-pc = {
            hostname = "daniel-njlab-pc";
            user = "shogo";
          };
          rpi5 = {
            hostname = "rpi5";
            user = "shogo";
          };
          raspberry-pi-home = {
            hostname = "raspberry-pi-home";
            user = "shogo";
          };

          # all hosts
          "*" = {
            compression = true;
          };
        };
      };
    };
}
