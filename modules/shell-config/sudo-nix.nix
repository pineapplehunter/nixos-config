{ writeShellScriptBin }:
writeShellScriptBin "sudo-nix" ''
  CMD=$1
  shift
  sudo $(which-nix $CMD) "$@"
''
