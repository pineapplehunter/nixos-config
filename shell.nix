{ lib
, writeShellScriptBin
, nix-output-monitor
, nvd
, nixos-rebuild
, mkShellNoCC
, home-manager
}:

let
  inherit (lib) getExe;
  build-script = writeShellScriptBin "build" ''
    ${getExe nix-output-monitor} build ".#nixosConfigurations.$HOST.config.system.build.toplevel" "$@"
    exit $?
  '';
  diff-script = writeShellScriptBin "diff" ''
    set -e
    ${getExe build-script} "$@"
    if [ $(readlink -f ./result) = $(readlink -f /run/current-system) ]; then
      echo All packges up to date!
      exit 1
    fi
    ${getExe nvd} diff /run/current-system ./result
  '';
  switch-script = writeShellScriptBin "switch" ''
    set -e
    ${getExe diff-script} "$@"
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
    sudo ${getExe nixos-rebuild} switch --flake ".#$HOST" "$@"
  '';
  boot-script = writeShellScriptBin "boot" ''
    set -e
    ${getExe build-script} "$@"
    sudo echo switching boot
    sudo ${getExe nixos-rebuild} boot --flake ".#$HOST"
  '';
  update-script = writeShellScriptBin "update" ''
    set -e
    git pull
    nix flake update
    ${getExe switch-script} "$@"
  '';
  home-build-script = writeShellScriptBin "home-build" ''
    ${getExe home-manager} build --flake ".#$USER" "$@"
    exit $?
  '';
  home-diff-script = writeShellScriptBin "home-diff" ''
    set -e
    ${getExe home-build-script} "$@"
    if [ $(readlink -f ./result) = $(readlink -f $HOME/.local/state/nix/profiles/home-manager) ]; then
      echo All packges up to date!
      exit 1
    fi
    ${getExe nvd} diff $HOME/.local/state/nix/profiles/home-manager ./result
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
    ${getExe home-manager} switch --flake ".#$USER" "$@"
  '';
  home-update-script = writeShellScriptBin "home-update" ''
    set -e
    git pull
    nix flake update
    ${getExe home-switch-script} "$@"
  '';
in
mkShellNoCC {
  name = "nixos-config";
  packages = [
    build-script
    switch-script
    diff-script
    update-script
    boot-script

    home-build-script
    home-diff-script
    home-switch-script
    home-update-script

    nvd
    nix-output-monitor
  ];
  shellHook = ''
    export HOST=`hostname`
    export USER=`whoami`
  '';
}
