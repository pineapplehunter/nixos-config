{
  flake.homeModules.shogo = {
    home.packages = [ ];

    programs.git.settings.user = {
      name = "Shogo Takata";
      email = "peshogo@gmail.com";
    };
  };
}
