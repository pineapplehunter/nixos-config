{
  flake.homeModules.kpro =
    { config, ... }:
    {
      programs = {
        pi-coding-agent.githubFetch.enable = true;
        ssh = {
          enable = true;
          settings = {
            kpro-njlab = {
              hostname = "kpro-njlab";
              user = "takata";
              identityFile = "${config.home.homeDirectory}/.ssh/cradsec_takata";
            };
          };
        };
        git.settings.user = {
          name = "Shogo Takata";
          email = "shogo-takata@st.go.tuat.ac.jp";
        };
      };
    };
}
