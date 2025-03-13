#!/usr/bin/env bash
set -eou pipefail

usage(){
  echo "usage: os   build|switch|boot|diff|expire [args...]"
  echo "       home build|switch|boot|diff        [args...]"
  exit 1
}

# parse args #######################################

kind="$(basename "$0")"
if [ "$kind" != os ] && [ "$kind" != home ]; then
  [ "$#" -lt 2 ] && usage
  kind=$1
  shift
else
  [ "$#" -lt 1 ] && usage
fi
cmd=$1
shift
args=("$@")

## os ##############################################

function os-users {
  nix eval ".#nixosConfigurations.$HOST.config.users.users" \
    --apply 'users: builtins.mapAttrs (u: v: {inherit (v) isNormalUser; name=u;}) users' --json \
  | jq '.[] | select(.isNormalUser) | .name' -r
}

function os-home-expire {
  users | while read -r u; do
    cd /
    sudo su "$u" -c "home-manager expire-generations 0" |& tail -n1
  done
}

function os-build {
  nom build ".#nixosConfigurations.$HOST.config.system.build.toplevel" "${args[@]}"
}

function os-diff {
  os-build
  if [ "$(readlink -f ./result)" = "$(readlink -f /run/current-system)" ]; then
    echo All packges up to date!
    exit 1
  fi
  nvd diff /run/current-system ./result
}

function os-switch {
  os-diff
  function yes_or_no {
    while true; do
      read -rp "$* [y/n]: " yn
      case $yn in
        [Yy]*) return 0  ;;
        [Nn]*) echo "Aborted" ; return 1 ;;
      esac
    done
  }
  yes_or_no "do you want to commit and update?"
  sudo echo starting upgrade
  git commit -p || true
  sudo nixos-rebuild switch --flake ".#$HOST" "${args[@]}"
  os-home-expire
}

function os-boot {
  os-build
  sudo echo switching boot
  sudo nixos-rebuild boot --flake ".#$HOST"
}

function os-update {
  set -x
  git pull
  nix flake update nixpkgs
  if ! git diff --exit-code --quiet HEAD -- flake.lock; then
    nix flake update
  fi
  os-switch || git checkout HEAD -- flake.lock
  set +x
}

## home ############################################

function home-build {
  nom build ".#homeConfigurations.$HOME_CONFIG_NAME.activationPackage" "${args[@]}"
}

function home-diff {
  home-build
  if [ "$(readlink -f ./result)" = "$(readlink -f "$HOME/.local/state/nix/profiles/home-manager")" ]; then
    echo All packges up to date!
    exit 1
  fi
  nvd diff "$HOME/.local/state/nix/profiles/home-manager" ./result
}

function home-switch {
  home-diff
  function yes_or_no {
    while true; do
      read -rp "$* [y/n]: " yn
      case $yn in
        [Yy]*) return 0  ;;
        [Nn]*) echo "Aborted" ; return 1 ;;
      esac
    done
  }
  yes_or_no "do you want to commit and update?"
  echo starting switch
  git commit -p || true
  home-manager switch -b "hm-backup" --flake ".#$HOME_CONFIG_NAME" "${args[@]}"
  home-manager expire-generations 0 |& tail -n1
}

function home-update {
  git pull
  nix flake update nixpkgs
  if ! git diff --exit-code --quiet HEAD -- flake.lock; then
    nix flake update
  fi
  home-switch || git checkout HEAD -- flake.lock
}

# main ###############################################

function os-cmd {
  case "$cmd" in
    build) os-build;;
    switch) os-switch;;
    diff) os-diff;;
    update) os-update;;
    boot) os-boot;;
    expire) os-home-expire;;
    *) echo unknown command && usage;;
  esac
}

function home-cmd {
  case "$cmd" in
    build) home-build;;
    diff) home-diff;;
    switch) home-switch;;
    update) home-update;;
    *) echo unknown command && usage;;
  esac
}

function main {
  case $kind in
    os) os-cmd;;
    home) home-cmd;;
    *) echo unknown kind && usage;;
  esac
}

main
