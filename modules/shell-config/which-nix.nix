{ writeShellScriptBin }:
writeShellScriptBin "which-nix" ''
  export cmd="$1"
  export nixpkgs=$(cat /etc/nix/registry.json | jq '.flakes[] | select(.from.id | contains("nixpkgs")) | .to.path' -r)
  export NIXPKGS_ALLOW_UNFREE=1

  if [ -z $cmd ]; then
    echo "Usage: which-nix [ command | command@package ]"
    exit 1
  fi

  if [[ $cmd = *@* ]]; then
    export cmd_no_at=$(echo $cmd | cut -d "@" -f 1)
    export cmd_package=$(echo $cmd | cut -d "@" -f 2)
    nix shell "$nixpkgs#$cmd_package" --impure -c which "$cmd_no_at"
  else
    nix shell "$nixpkgs#$cmd" --impure -c which "$cmd"
  fi
''
