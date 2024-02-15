#!/usr/bin/env bash
export cmd="$1"
if [[ $cmd = *@* ]]; then
  export cmd_no_at=$(echo $cmd | cut -d "@" -f 1)
  export cmd_package=$(echo $cmd | cut -d "@" -f 2)
  nix build nixpkgs#$cmd_package --no-link
  echo $(nix path-info "nixpkgs#$cmd_package" 2> /dev/null)/bin/$cmd_no_at
else
  nix build nixpkgs#$cmd --no-link
  echo $(nix path-info nixpkgs#$cmd 2> /dev/null)/bin/$cmd
fi
