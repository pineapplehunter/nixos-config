{
  pkgs ? import <nixpkgs> { },
}:

let
  inherit (pkgs)
    writeShellScriptBin
    mkShellNoCC
    nvd
    nix-output-monitor
    home-manager
    nixos-rebuild
    statix
    ;
  inherit (pkgs.lib) getExe;
  expire-home-manager = writeShellScriptBin "expire-home-manager" ''
    users(){
      nix eval ".#nixosConfigurations.$HOST.config.users.users" \
        --apply 'users: builtins.mapAttrs (u: v: {inherit (v) isNormalUser; name=u;}) users' --json \
      | jq '.[] | select(.isNormalUser) | .name' -r
    }
    users | while read -r u; do
      cd /
      sudo su $u -c "${getExe home-manager} expire-generations 0" |& tail -n1
    done
  '';
  os-build-script = writeShellScriptBin "os-build" ''
    set -eou pipefail
    nom build ".#nixosConfigurations.$HOST.config.system.build.toplevel" "$@"
    exit $?
  '';
  os-diff-script = writeShellScriptBin "os-diff" ''
    set -eou pipefail
    ${getExe os-build-script} "$@"
    if [ $(readlink -f ./result) = $(readlink -f /run/current-system) ]; then
      echo All packges up to date!
      exit 1
    fi
    nvd diff /run/current-system ./result
  '';
  os-switch-script = writeShellScriptBin "os-switch" ''
    set -eou pipefail
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
    git commit -p || true
    sudo nixos-rebuild switch --flake ".#$HOST" "$@"
    ${getExe expire-home-manager}
  '';
  os-boot-script = writeShellScriptBin "os-boot" ''
    set -eou pipefail
    ${getExe os-build-script} "$@"
    sudo echo switching boot
    sudo nixos-rebuild boot --flake ".#$HOST"
  '';
  os-update-script = writeShellScriptBin "os-update" ''
    set -eou pipefail
    git pull
    nix flake update nixpkgs
    git diff --exit-code --quiet HEAD -- flake.lock && exit 1 || true
    nix flake update
    ${getExe os-switch-script} "$@" || git checkout HEAD -- flake.lock
  '';
  home-build-script = writeShellScriptBin "home-build" ''
    set -eou pipefail
    nom build ".#homeConfigurations.$HOME_CONFIG_NAME.activationPackage" "$@"
    exit $?
  '';
  home-diff-script = writeShellScriptBin "home-diff" ''
    set -eou pipefail
    ${getExe home-build-script} "$@"
    if [ $(readlink -f ./result) = $(readlink -f $HOME/.local/state/nix/profiles/home-manager) ]; then
      echo All packges up to date!
      exit 1
    fi
    nvd diff $HOME/.local/state/nix/profiles/home-manager ./result
  '';
  home-switch-script = writeShellScriptBin "home-switch" ''
    set -eou pipefail
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
    git commit -p || true
    home-manager switch -b "hm-backup" --flake ".#$HOME_CONFIG_NAME" "$@"
    home-manager expire-generations 0 |& tail -n1
  '';
  home-update-script = writeShellScriptBin "home-update" ''
    set -eou pipefail
    git pull
    nix flake update nixpkgs
    git diff --exit-code --quiet HEAD -- flake.lock && exit 1 || true
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

    expire-home-manager

    nvd
    nix-output-monitor
    home-manager
    nixos-rebuild
    statix
  ];
  shellHook = ''
    export HOST=`hostname`
  '';
}
