{ ... }:
{
  imports = [
    ./sandbox.nix
    ./clipboard.nix
    ./git-signing.nix
    ./github-fetch.nix
    ./codex-broker.nix
    ./nix-daemon.nix
    ./remote-ticket.nix
  ];
}
