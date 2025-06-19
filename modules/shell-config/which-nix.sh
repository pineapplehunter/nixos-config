#!/usr/bin/env @shell@

cmd="$1"
nixpkgs=$(@cat@ /etc/nix/registry.json | @jq@ '.flakes[] | select(.from.id | contains("nixpkgs")) | .to.path' -r)
export NIXPKGS_ALLOW_UNFREE=1

if [ -z "$cmd" ]; then
  echo "Usage: $0 [ command | command@package ]"
  exit 1
fi

if [[ $cmd = *@* ]]; then
  cmd_no_at=$(echo "$cmd" | cut -d "@" -f 1)
  cmd_package=$(echo "$cmd" | cut -d "@" -f 2)
  PATH="" @nix@ shell "$nixpkgs#$cmd_package" --impure -c @which@ "$cmd_no_at"
else
  PATH="" @nix@ shell "$nixpkgs#$cmd" --impure -c @which@ "$cmd"
fi
