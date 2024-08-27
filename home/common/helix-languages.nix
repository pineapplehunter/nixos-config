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
  ];
}
