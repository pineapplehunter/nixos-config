{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.webcord
    pkgs.slack
    pkgs.unityhub
  ];
}
