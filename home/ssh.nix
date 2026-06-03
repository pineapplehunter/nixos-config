{
  flake.homeModules.ssh = {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        linode = {
          hostname = "ihavenojob.work";
          user = "shogo";
          identityFile = "~/.ssh/id_ed25519";
          port = 13428;
          setEnv = [ "TERM=xterm-256color" ];
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
        raspberry-pi-home = {
          hostname = "raspberry-pi-home";
          user = "shogo";
        };
        "*" = {
          compression = true;
        };
      };
    };
  };
}
