{ kconfig-tree-sitter, caddy-tree-sitter, ... }:
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
      config.pyright.disableTaggedHints = true;
    };
    buf = {
      command = "buf";
      args = [
        "beta"
        "lsp"
      ];
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
      name = "caddy";
      scope = "source.caddy";
      comment-token = "#";
      file-types = [
        { glob = "Caddyfile"; }
      ];
      injection-regex = "caddy";
    }
    {
      name = "python";
      language-servers = [
        "ruff"
        "pyright"
        "pylsp"
      ];
    }
    {
      name = "protobuf";
      language-servers = [ "buf" ];
    }
  ];
  grammar = [
    {
      name = "kconfig";
      source.path = kconfig-tree-sitter;
    }
    {
      name = "caddy";
      source.path = caddy-tree-sitter;
    }
  ];
}
