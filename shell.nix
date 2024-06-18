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
    sudo ${getExe nixos-rebuild} switch --flake ".#$HOST"
  '';
  boot-script = writeShellScriptBin "boot" ''
    set -e
    ${getExe build-script} "$@"
    sudo echo switching boot
    sudo ${getExe nixos-rebuild} boot --flake ".#$HOST"
  '';
  update-script = writeShellScriptBin "update" ''
    git pull
    nix flake update
    ${getExe switch-script} "$@"
  '';
  build-home-script = writeShellScriptBin "build-home" ''
    ${getExe home-manager} build --flake ".#$USER" "$@"
    exit $?
  '';
  diff-home-script = writeShellScriptBin "diff-home" ''
    set -e
    ${getExe build-home-script} "$@"
    if [ $(readlink -f ./result) = $(readlink -f $HOME/.local/state/nix/profiles/home-manager) ]; then
      echo All packges up to date!
      exit 1
    fi
    ${getExe nvd} diff $HOME/.local/state/nix/profiles/home-manager ./result
  '';
  switch-home-script = writeShellScriptBin "switch-home" ''
    set -e
    ${getExe diff-home-script} "$@"
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
  update-home-script = writeShellScriptBin "update-home" ''
    git pull
    nix flake update
    ${getExe switch-home-script} "$@"
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

    build-home-script
    diff-home-script
    switch-home-script
    update-home-script

    nvd
    nix-output-monitor
  ];
  shellHook = ''
    export HOST=`hostname`
    export USER=`whoami`
  '';
}
