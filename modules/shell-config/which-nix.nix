{ writeShellScriptBin, nix, nixpkgs, lib }:
writeShellScriptBin "which-nix" ''
  export cmd="$1"
  if [[ $cmd = *@* ]]; then
    export cmd_no_at=$(echo $cmd | cut -d "@" -f 1)
    export cmd_package=$(echo $cmd | cut -d "@" -f 2)
    echo $(${lib.getExe nix} path-info "${nixpkgs.url}#$cmd_package")/bin/$cmd_no_at
  else
    echo $(${lib.getExe nix} "${nixpkgs.url}#$cmd")/bin/$cmd
  fi
''
