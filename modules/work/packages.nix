{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.act
    pkgs.gitlab-ci-local
    pkgs.unityhub
  ];
}
