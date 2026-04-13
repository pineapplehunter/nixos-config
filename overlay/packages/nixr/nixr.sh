usage(){
  cat << EOF
nixr --remote *nix-ssh-client* *flake-refs*
EOF
}

green(){
  echo -e "\e[32m$*\e[0m"
}

red(){
  echo -e "\e[31m$*\e[0m"
}

any-error () {
  red Some error occured while building
  usage
  exit 1
}

trap any-error EXIT

DERIVATION_PATHS=()
REMOTE=none

while [[ -n "${1:-}" ]]; do
  case "$1" in
    --remote|-r)
      REMOTE=$2
      shift
      ;;
    *)
      while read -r path; do
        DERIVATION_PATHS+=("$path")
      done < <(nix path-info "$1" --derivation)
      ;;
  esac
  shift
done

BUILT_PATHS=()
REMOTE_BUILT_PATHS=()
for drv in "${DERIVATION_PATHS[@]}"; do
  BUILT_PATHS+=("$drv^*")
  REMOTE_BUILT_PATHS+=("$(printf "%q" "$drv^*")")
done

nix copy --to ssh:"$REMOTE" "${DERIVATION_PATHS[@]}"
ssh "$REMOTE" nix -L build --no-link "${REMOTE_BUILT_PATHS[@]}"
nix build --no-require-sigs --extra-trusted-substituters ssh:"$REMOTE" "${BUILT_PATHS[@]}"

# reset trap
trap - EXIT
