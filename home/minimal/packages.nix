{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
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
      ncdu
      nix-output-monitor
      nix-search-cli
      nix-tree
      nixpkgs-review
      npins
      ripgrep
    ]
    ++ lib.optionals isDarwin [ pkgs.iterm2 ];
}
