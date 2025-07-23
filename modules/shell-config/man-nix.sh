#!/usr/bin/env bash
set -euo pipefail

cmd="$1"
nixpkgs=$(@jq@ '.flakes[] | select(.from.id | contains("nixpkgs")) | .to.path' -r < /etc/nix/registry.json || echo "github:nixos/nixpkgs?ref=nixos-unstable")
export NIXPKGS_ALLOW_UNFREE=1

if [ -z "$cmd" ]; then
  echo "Usage: $0 [ command | command@package ]"
  exit 1
fi

if [[ $cmd = *@* ]]; then
  cmd_name=$(echo "$cmd" | cut -d "@" -f 1)
  cmd_package=$(echo "$cmd" | cut -d "@" -f 2)
else
  cmd_name="$cmd"
  cmd_package="$cmd"
fi

@nix@ shell "$nixpkgs#$cmd_package" --impure -c @man@ "$cmd_name"

