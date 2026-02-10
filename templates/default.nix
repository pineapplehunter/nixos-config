{
  flake.templates = {
    shell = {
      path = ./shell;
      description = "simple shell";
    };
    rust = {
      path = ./rust;
      description = "simple shell with rust";
    };
    package = {
      path = ./package;
      description = "simple package";
    };
  };
}
