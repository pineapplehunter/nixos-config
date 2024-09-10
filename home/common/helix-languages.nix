{ ... }:
{
  language-server.nixd.command = "nixd";
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
      name = "kconfig";
      scope = "source.kconfig";
      comment-token = "#";
      file-types = [ { glob = "Kconfig"; } ];
    }
  ];
  grammar = [
    {
      name = "kconfig";
      source = {
        git = "https://github.com/tree-sitter-grammars/tree-sitter-kconfig";
        rev = "486fea71f61ad9f3fd4072a118402e97fe88d26c";
      };
    }
  ];
}
