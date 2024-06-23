{ lib
, nixd
}:
{
  language-server.nixd.command = lib.getExe nixd;
  language = [{
    name = "nix";
    # auto-format = true;
    language-servers = [ "nixd" "nil" ];
  }];
}
