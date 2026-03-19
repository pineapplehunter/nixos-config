# disable wrapping when bootstrapping
if [[ -n ${BUBBLEUNWRAP:-} ]]; then
  exec "$EXECUTABLE" "$@"
fi

if [ -z "${EXECUTABLE:-}" ];then
  echo The environment variable EXECUTABLE is not set
  exit 1
fi

if [ -z "${PROJECT_ROOT_FILE:-}" ];then
  echo The environment variable PROJECT_ROOT_FILE is not set
  exit 1
fi

pushd . > /dev/null
while [[ ! -f "$PROJECT_ROOT_FILE" ]]; do
  if [[ "$PWD" == / ]]; then
    echo "$PROJECT_ROOT_FILE" not found
    exit 1
  fi
  cd ..
done
PROJECT_ROOT=$PWD
popd > /dev/null || exit 1

bwrap_args=(
  --unshare-all
  --share-net
  --tmpfs /tmp
  --dev /dev
  --proc /proc
  --ro-bind /nix /nix
  --ro-bind "$HOME" "$HOME"
  --bind "$PROJECT_ROOT" "$PROJECT_ROOT"
)

# add nessesary etc dirs
ETC_ENTRIES=(
  host.conf
  hosts
  localtime
  nsswitch.conf
  pki
  resolv.conf
)
for e in "${ETC_ENTRIES[@]}"; do
  bwrap_args+=(--ro-bind-try "/etc/$e" "/etc/$e")
done

# add nessesary opencode dirs
OPENCODE_ENTRIES=(
  .cache/opencode
  .config/opencode
  .local/share/opencode
  .local/state/opencode
)
for e in "${OPENCODE_ENTRIES[@]}"; do
  bwrap_args+=(--bind "/$HOME/$e" "/$HOME/$e")
done

# Parse special arguments (only before first non-@ argument or @@)
while [[ "${1:-}" == @* ]]; do
  case "$1" in
    @net)
      bwrap_args+=(--share-net)
      ;;
    @@)
      break
      ;;
    *)
      echo error while processing wrapping arguments "$1"
      exit 1
      ;; 
  esac
  shift
done

exec bwrap "${bwrap_args[@]}" -- "$EXECUTABLE" "$@"