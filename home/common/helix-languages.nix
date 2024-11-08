{ kconfig-tree-sitter, ... }:
{
  language-server = {
    nixd.command = "nixd";
    ruff = {
      command = "ruff";
      args = [ "server" ];
    };
    pyright = {
      command = "pyright-langserver";
      args = [ "--stdio" ];
    };
  };
  language = [
    {
      name = "nix";
      language-servers = [
        "nixd"
        "nil"
      ];
    }
    {
      name = "markdown";
      soft-wrap.enable = true;
    }
    {
      name = "latex";
      soft-wrap.enable = true;
    }
    {
      name = "typst";
      soft-wrap.enable = true;
    }
    {
      name = "kconfig";
      scope = "source.kconfig";
      comment-token = "#";
      file-types = [
        { glob = "Kconfig"; }
        { glob = "kconfig"; }
      ];
      injection-regex = "kconfig";
    }
    {
      name = "python";
      language-servers = [
        "ruff"
        "pyright"
        "pylsp"
      ];
    }
  ];
  grammar = [
    {
      name = "kconfig";
      source.path = kconfig-tree-sitter;
    }
  ];
}
