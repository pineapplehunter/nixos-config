{
  lib,
  writeShellScriptBin,
  nix-output-monitor,
  nvd,
  nixos-rebuild,
  mkShellNoCC,
  home-manager,
}:

let
  inherit (lib) getExe;
  os-build-script = writeShellScriptBin "os-build" ''
    nom build ".#nixosConfigurations.$HOST.config.system.build.toplevel" "$@"
    exit $?
  '';
  os-diff-script = writeShellScriptBin "os-diff" ''
    set -e
    ${getExe os-build-script} "$@"
    if [ $(readlink -f ./result) = $(readlink -f /run/current-system) ]; then
      echo All packges up to date!
      exit 1
    fi
    nvd diff /run/current-system ./result
  '';
  os-switch-script = writeShellScriptBin "os-switch" ''
    set -e
    ${getExe os-diff-script} "$@"
    function yes_or_no {
        while true; do
            read -p "$* [y/n]: " yn
            case $yn in
                [Yy]*) return 0  ;;
                [Nn]*) echo "Aborted" ; return 1 ;;
            esac
        done
    }
    yes_or_no "do you want to commit and update?"
    sudo echo starting upgrade
    git commit -am "$(date -Iminutes)" || true
    sudo nixos-rebuild switch --flake ".#$HOST" "$@"
  '';
  os-boot-script = writeShellScriptBin "os-boot" ''
    set -e
    ${getExe os-build-script} "$@"
    sudo echo switching boot
    sudo nixos-rebuild boot --flake ".#$HOST"
  '';
  os-update-script = writeShellScriptBin "os-update" ''
    set -e
    git pull
    nix flake update
    ${getExe os-switch-script} "$@" || git checkout HEAD -- flake.lock
  '';
  home-build-script = writeShellScriptBin "home-build" ''
    nom build ".#homeConfigurations.$HOME_CONFIG_NAME.activationPackage" "$@"
    exit $?
  '';
  home-diff-script = writeShellScriptBin "home-diff" ''
    set -e
    ${getExe home-build-script} "$@"
    if [ $(readlink -f ./result) = $(readlink -f $HOME/.local/state/nix/profiles/home-manager) ]; then
      echo All packges up to date!
      exit 1
    fi
    nvd diff $HOME/.local/state/nix/profiles/home-manager ./result
  '';
  home-switch-script = writeShellScriptBin "home-switch" ''
    set -e
    ${getExe home-diff-script} "$@"
    function yes_or_no {
        while true; do
            read -p "$* [y/n]: " yn
            case $yn in
                [Yy]*) return 0  ;;
                [Nn]*) echo "Aborted" ; return 1 ;;
            esac
        done
    }
    yes_or_no "do you want to commit and update?"
    echo starting switch
    git commit -am "$(date -Iminutes)-home" || true
    home-manager switch -b "hm-backup" --flake ".#$HOME_CONFIG_NAME" "$@"
  '';
  home-update-script = writeShellScriptBin "home-update" ''
    set -e
    git pull
    nix flake update
    ${getExe home-switch-script} "$@" || git checkout HEAD -- flake.lock
  '';
in
mkShellNoCC {
  name = "nixos-config";
  packages = [
    os-build-script
    os-switch-script
    os-diff-script
    os-update-script
    os-boot-script

    home-build-script
    home-diff-script
    home-switch-script
    home-update-script

    nvd
    nix-output-monitor
    home-manager
    nixos-rebuild
  ];
  shellHook = ''
    export HOST=`hostname`
  '';
}
