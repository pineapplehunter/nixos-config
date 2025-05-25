{ ... }:
{
  language-server = {
    nixd.command = "nixd";
    ruff = {
      command = "ruff";
      args = [
        "server"
        "-q"
        "--preview"
      ];
    };
    basedpyright = {
      command = "basedpyright-langserver";
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
      name = "python";
      language-servers = [
        "ruff"
        "basedpyright"
      ];
    }
    {
      name = "protobuf";
      language-servers = [ "buf" ];
    }
    {
      name = "meson";
      formatter = {
        command = "meson";
        args = [
          "fmt"
          "-"
        ];
      };
    }
  ];
}
