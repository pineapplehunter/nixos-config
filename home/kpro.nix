{
  flake.homeModules.kpro =
    { config, ... }:
    {
      programs = {
        ssh = {
          enable = true;
          matchBlocks = {
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
