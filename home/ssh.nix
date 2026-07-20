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
          action = {
            hostname = "action";
            user = "shogo";
          };
          beast = {
            hostname = "beast";
            user = "shogo";
          };
          daniel-njlab-pc = {
            hostname = "daniel-njlab-pc";
            user = "shogo";
          };
          kpro-njlab = {
            hostname = "kpro-njlab";
            user = "takata";
          };
          kpro-takata = {
            hostname = "kpro-takata";
            user = "takata";
          };
          raspberry-pi-home = {
            hostname = "raspberry-pi-home";
            user = "shogo";
          };
          rpi5 = {
            hostname = "rpi5";
            user = "shogo";
          };

          # ghostty workarounds
          "uptermd.upterm.dev" = {
            setEnv = "TERM=xterm-256color";
          };

          # all hosts
          "*" = {
            compression = true;
          };
        };
      };
    };
}
