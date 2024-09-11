{ kconfig-tree-sitter, ... }:
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
      file-types = [
        { glob = "Kconfig"; }
        { glob = "kconfig"; }
      ];
      injection-regex = "kconfig";
    }
  ];
  grammar = [
    {
      name = "kconfig";
      source.path = kconfig-tree-sitter;
    }
  ];
}
