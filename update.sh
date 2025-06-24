#!/usr/bin/env bash
set -eou pipefail

# check commands ################################
for cmd in nix nixos-rebuild home-manager nvd; do
  command -v $cmd > /dev/null || echo command $cmd does not exist
done

HOMEMANAGER=$(which home-manager || echo NOT_FOUND)

usage(){
  echo "usage: os   build|switch|boot|diff|expire            [args...]"
  echo "       home build|switch|boot|diff|expire|fix-darwin [args...]"
  exit 1
}

# utils ###########################################

function yes_or_exit {
  prompt="$*"
  while true; do
    read -rp "$prompt [y/n]: " yn
    case $yn in
      [Yy]*)
        return 0
        ;;
      [Nn]*)
        echo "Aborted"
        exit 1
        ;;
    esac
  done
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
  os-users | while read -r u; do
    cd /
    sudo sudo -u "$u" LANG=C "$HOMEMANAGER" expire-generations 0 2>&1 | grep -v No | grep -v Cannot || true
    sudo sudo -u "$u" LANG=C nix profile wipe-history || true
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
  yes_or_exit "do you want to commit and update?"
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
  git pull
  nix flake update nixpkgs
  if ! git diff --exit-code --quiet HEAD -- flake.lock; then
    nix flake update
  fi
  os-switch || git checkout HEAD -- flake.lock
}

## home ############################################

function home-expire {
  LANG=C $HOMEMANAGER expire-generations 0 2>&1 | grep -v No | grep -v Cannot || true
  LANG=C nix profile wipe-history || true
}

function home-build {
  nom build ".#homeConfigurations.$HOME_CONFIG_NAME.activationPackage" "${args[@]}"
}

function home-diff {
  home-build
  if [ "$(readlink -f ./result)" = "$(readlink -f "$HOME/.local/state/nix/profiles/home-manager")" ]; then
    echo All packges up to date!
    exit 1
  fi

  if [ -e "$HOME/.local/state/nix/profiles/home-manager" ]; then
    nvd diff "$HOME/.local/state/nix/profiles/home-manager" ./result
  else
    echo no previous home-manager output. skipping diff.
  fi
}

function home-switch {
  home-diff
  yes_or_exit "do you want to commit and update?"
  echo starting switch
  git commit -p || true
  $HOMEMANAGER switch -b "hm-backup" --flake ".#$HOME_CONFIG_NAME" "${args[@]}"
  home-expire
}

function home-update {
  git pull
  nix flake update nixpkgs
  if ! git diff --exit-code --quiet HEAD -- flake.lock; then
    nix flake update
  fi
  home-switch || git checkout HEAD -- flake.lock
}

function home-fix-darwin {
  echo Fixing darwin paths
  echo adding nix daemon to /etc/zshrc
  cat << EOF | sudo tee -a /etc/zshrc
# Nix
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi
# End Nix
EOF
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
    expire) home-expire;;
    fix-darwin) home-fix-darwin;;
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
