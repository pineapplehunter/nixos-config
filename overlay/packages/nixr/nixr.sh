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
NIX_BUILD_OPTIONS=()
while [[ -n "${1:-}" ]]; do
  case "$1" in
    --remote|-r)
      REMOTE=$2
      shift
      ;;
    --)
      shift
      NIX_BUILD_OPTIONS=("$@")
      break
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
for drv in "${DERIVATION_PATHS[@]}"; do
  BUILT_PATHS+=("$drv^*")
done

nix copy --to ssh:"$REMOTE" "${DERIVATION_PATHS[@]}"
ssh "$REMOTE" -- "$(printf "%q " nix build --no-link --log-format bar-with-logs "${NIX_BUILD_OPTIONS[@]}" "${BUILT_PATHS[@]}")"
nix build --no-require-sigs --extra-trusted-substituters ssh:"$REMOTE" "${BUILT_PATHS[@]}"

# reset trap
trap - EXIT
