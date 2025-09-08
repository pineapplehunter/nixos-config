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
    git = {
      userName = "Shogo Takata";
      userEmail = "shogo-takata@st.go.tuat.ac.jp";
    };
  };
}
