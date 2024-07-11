{
  writeShellScriptBin,
  confirm ? false,
  lib,
  nix,
  jq,
}:
let
  name = "not-found-exec-shell";
in
writeShellScriptBin name ''
  export cmd="$1"
  export nixpkgs=$(cat /etc/nix/registry.json | jq '.flakes[] | select(.from.id | contains("nixpkgs")) | .to.path' -r)
  shift

  if [ -z $cmd ]; then
    echo "Usage: ${name} [ command | command@package ]"
    exit 1
  fi

  ${lib.optionalString confirm ''
    if [[ $cmd = *@* ]]; then
      export cmd_no_at=$(echo $cmd | cut -d "@" -f 1)
      export cmd_package=$(echo $cmd | cut -d "@" -f 2)
      echo "Command '$cmd_no_at' not found, do you want to try $cmd_no_at from $nixpkgs#$cmd_package? [y/N]: "
    else
      echo "Command '$cmd' not found, do you want to try $cmd from nixpkgs? [y/N]: "
    fi 
  ''}

  ${lib.optionalString confirm "if read -q; then"}
  if [[ $cmd = *@* ]]; then
    export cmd_no_at=$(echo $cmd | cut -d "@" -f 1)
    export cmd_package=$(echo $cmd | cut -d "@" -f 2)
    NIXPKGS_ALLOW_UNFREE=1 ${lib.getExe nix} shell "$nixpkgs#$cmd_package" --impure -c $cmd_no_at $*
  else
    NIXPKGS_ALLOW_UNFREE=1 ${lib.getExe nix} shell "$nixpkgs#$cmd" --impure -c $cmd $*
  fi
  ${lib.optionalString confirm "fi"}
''
