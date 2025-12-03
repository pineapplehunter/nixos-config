#!/usr/bin/env bash
set -Eeou pipefail

# check commands ################################
for cmd in nix nvd; do
  command -v $cmd > /dev/null || echo command $cmd does not exist
done

HOMEMANAGER=$(command -v home-manager || echo NOT_FOUND)

usage(){
  PNAME=$(basename "${0:-update.sh}")
  if [[ "$PNAME" == os || "$PNAME" == home ]]; then
    echo "usage: $PNAME [cmd] [nix_args...]" >&2
  else
    echo "usage: $PNAME [os|home] [cmd] [nix_args...]" >&2
  fi
  cat << EOF >&2
cmd:
  build      : Build the configuration
  switch     : Switch to new configuration
  boot       : Build and set new configuration on next boot
  diff       : Show difference of the current and new closure
  expire     : Remove old configurations
  fix-darwin : Fix nix installation after update (only home)
EOF
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
  nix eval ".#nixosConfigurations.$HOST.config.users.users" --json \
  | jq 'map_values(select(.isNormalUser)) | keys[]' -r
}

function os-home-expire {
  os-users | while read -r u; do
    cd /
    sudo -u "$u" LANG=C "$HOMEMANAGER" expire-generations 0 2>&1 | grep -v No | grep -v Cannot || true
    sudo -u "$u" LANG=C nix profile wipe-history || true
  done
}

function os-generation-expire {
  sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +10
}

function os-expire {
  os-generation-expire
  os-home-expire
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
}

function os-boot {
  sudo nixos-rebuild boot --flake ".#$HOST" "${args[@]}"
}

function os-test {
  sudo nixos-rebuild test --flake ".#$HOST" "${args[@]}"
}

function os-update {
  git pull
  nix flake update nixpkgs
  if ! git diff --exit-code --quiet HEAD -- flake.lock; then
    nix flake update
    os-switch || git checkout HEAD -- flake.lock
  fi
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
}

function home-test {
  $HOMEMANAGER test -b "hm-backup" --flake ".#$HOME_CONFIG_NAME" "${args[@]}"
}

function home-update {
  git pull
  nix flake update nixpkgs
  if ! git diff --exit-code --quiet HEAD -- flake.lock; then
    nix flake update
    home-switch || git checkout HEAD -- flake.lock
  fi
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
  command -v nixos-rebuild > /dev/null || echo command nixos-rebuild does not exist
  case "$cmd" in
    boot) os-boot;;
    build) os-build;;
    diff) os-diff;;
    expire) os-expire;;
    switch) os-switch;;
    test) os-test;;
    update) os-update;;
    *) echo unknown command && usage;;
  esac
}

function home-cmd {
  command -v home-manager > /dev/null || echo command home-manager does not exist
  case "$cmd" in
    build) home-build;;
    diff) home-diff;;
    expire) home-expire;;
    fix-darwin) home-fix-darwin;;
    switch) home-switch;;
    test) home-test;;
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
