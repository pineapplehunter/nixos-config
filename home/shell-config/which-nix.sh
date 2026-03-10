if ! command -v nix > /dev/null; then
  echo nix command not found in PATH
  exit 1
fi

NIX=$(command -v nix)
WHICH=$(command -v which)

cmd="$1"
nixpkgs="github:nixos/nixpkgs?ref=nixos-unstable"
if [ -f /etc/nix/registry.json ]; then
  nixpkgs=$(jq '.flakes[] | select(.from.id | contains("nixpkgs")) | .to.path' -r < /etc/nix/registry.json || $nixpkgs)
fi
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

PATH="" "$NIX" shell "$nixpkgs#$cmd_package" --impure -c "$WHICH" "$cmd_name"
