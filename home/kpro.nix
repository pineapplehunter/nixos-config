{
  flake.homeModules.kpro = {
    programs = {
      ssh = {
        enable = true;
        settings = {
          kpro-njlab = {
            hostname = "kpro-njlab";
            user = "takata";
            identityFile = "~/.ssh/cradsec_takata";
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
