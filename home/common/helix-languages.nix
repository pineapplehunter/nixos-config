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
  ];
}
