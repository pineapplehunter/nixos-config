#!/usr/bin/env bash

cmd="$1"
nixpkgs=$(@jq@ '.flakes[] | select(.from.id | contains("nixpkgs")) | .to.path' -r < /etc/nix/registry.json)
export NIXPKGS_ALLOW_UNFREE=1
shift

if [ -z "$cmd" ]; then
  echo "Usage: $0 [ command | command@package ]"
  exit 1
fi

if [[ $cmd = *@* ]]; then
  cmd_name=$(echo "$cmd" | @cut@ -d "@" -f 1)
  cmd_package=$(echo "$cmd" | @cut@ -d "@" -f 2)
else
  cmd_name="$cmd"
  cmd_package="$cmd"
fi

if [ -n "@confirm@" ]; then
  echo "Command '$cmd_name' not found, do you want to try $cmd_name from $nixpkgs#$cmd_package? [y/N]: "
  read -r choice
  case "$choice" in
    y|Y ) ;;
    * ) echo abort; exit 1;;
  esac
fi

@nix@ shell "$nixpkgs#$cmd_package" --impure -c "$cmd_name" "$@"
