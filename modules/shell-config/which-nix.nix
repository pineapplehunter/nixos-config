{ writeShellScriptBin
, nix
, lib
,
}:
writeShellScriptBin "which-nix" ''
  export cmd="$1"
  export nixpkgs=$(cat /etc/nix/registry.json | jq '.flakes[] | select(.from.id | contains("nixpkgs")) | .to.path' -r)
  if [[ $cmd = *@* ]]; then
    export cmd_no_at=$(echo $cmd | cut -d "@" -f 1)
    export cmd_package=$(echo $cmd | cut -d "@" -f 2)
    nix build nixpkgs#$cmd_package --no-link
    echo $(${lib.getExe nix} path-info "$nixpkgs#$cmd_package" 2> /dev/null)/bin/$cmd_no_at
  else
    nix build nixpkgs#$cmd --no-link
    echo $(${lib.getExe nix} path-info "$nixpkgs#$cmd" 2> /dev/null)/bin/$cmd
  fi
''
