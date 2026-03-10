CMD=$1
CMD_FULL_PATH=$(which-nix "$CMD")
shift
sudo "$CMD_FULL_PATH" "$@"
