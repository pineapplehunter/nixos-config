{ writeShellScriptBin, confirm ? false, lib, nixpkgs, nix }:let 
  name = "not-found-exec-shell";
in
writeShellScriptBin name ''
  export cmd="$1"
  shift

  if [ -z $cmd ]; then
    echo "Usage: ${name} [ command | command@package ]"
    exit 1
  fi

  ${lib.optionalString confirm ''
  if [[ $cmd = *@* ]]; then
    export cmd_no_at=$(echo $cmd | cut -d "@" -f 1)
    export cmd_package=$(echo $cmd | cut -d "@" -f 2)
    echo "Command '$cmd_no_at' not found, do you want to try $cmd_no_at from ${nixpkgs.url}#$cmd_package? [y/N]: "
  else
    echo "Command '$cmd' not found, do you want to try $cmd from ${nixpkgs.url}? [y/N]: "
  fi 
  ''}

  ${lib.optionalString confirm ''if read -q; then''}
  if [[ $cmd = *@* ]]; then
    export cmd_no_at=$(echo $cmd | cut -d "@" -f 1)
    export cmd_package=$(echo $cmd | cut -d "@" -f 2)
    ${nix}/bin/nix shell "${nixpkgs.url}#$cmd_package" -c $cmd_no_at $*
  else
    ${nix}/bin/nix shell "${nixpkgs.url}#$cmd" -c $cmd $*
  fi
  ${lib.optionalString confirm ''fi''}
''
