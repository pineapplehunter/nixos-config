{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin system;
in
{
  config.home.packages =
    with pkgs;
    [
      attic-client
      fd
      ffmpegthumbnailer
      file
      helix
      htop
      jq
      nix-output-monitor
      nix-search-cli
      nix-tree
      nixpkgs-review
      npins
      ripgrep
    ]
    ++ lib.optionals isDarwin [ pkgs.iterm2 ]
    # ncdu broken on x86_64-darwin
    # https://github.com/ziglang/zig/issues/24974
    ++ lib.optionals (system != "x86_64-darwin") [ ncdu ];
}
