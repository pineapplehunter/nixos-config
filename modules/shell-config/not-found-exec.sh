#!/usr/bin/env @shell@

cmd="$1"
nixpkgs=$(@cat@ /etc/nix/registry.json | @jq@ '.flakes[] | select(.from.id | contains("nixpkgs")) | .to.path' -r)
export NIXPKGS_ALLOW_UNFREE=1
shift

if [ -z "$cmd" ]; then
  echo "Usage: $0 [ command | command@package ]"
  exit 1
fi

if [ -n "@confirm@" ]; then
  if [[ $cmd = *@* ]]; then
    cmd_no_at=$(echo "$cmd" | cut -d "@" -f 1)
    cmd_package=$(echo "$cmd" | cut -d "@" -f 2)
    echo "Command '$cmd_no_at' not found, do you want to try $cmd_no_at from $nixpkgs#$cmd_package? [y/N]: "
  else
    echo "Command '$cmd' not found, do you want to try $cmd from nixpkgs? [y/N]: "
  fi
  read -r -p "Continue (y/n)?" choice
  case "$choice" in
    y|Y ) ;;
    * ) echo abort; exit 1;;
  esac
fi

if [[ $cmd = *@* ]]; then
  cmd_no_at=$(echo "$cmd" | cut -d "@" -f 1)
  cmd_package=$(echo "$cmd" | cut -d "@" -f 2)
  @nix@ shell "$nixpkgs#$cmd_package" --impure -c "$cmd_no_at" "$@"
else
  @nix@ shell "$nixpkgs#$cmd" --impure -c "$cmd" "$@"
fi
