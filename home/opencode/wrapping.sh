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

ARG_PATH=$(mktemp)

append_args(){
  for arg in "$@"; do
    echo -ne "$arg\0" >> "$ARG_PATH"
  done
}

bwrap_args=(
  --unshare-all
  --die-with-parent
  --cap-drop ALL
  --share-net
  --tmpfs /tmp
  --dev /dev
  --proc /proc
  --ro-bind /nix /nix
  --ro-bind "$HOME" "$HOME"
  --tmpfs "$HOME/.ssh" # hide ssh keys
  --tmpfs /etc
  --tmpfs /run
  --tmpfs /var
  --bind "$PROJECT_ROOT" "$PROJECT_ROOT"
  --setenv LANG C
)

append_args "${bwrap_args[@]}"

# add nessesary etc dirs
RO_ENTRIES=(
  /etc/gai.conf
  /etc/host.conf
  /etc/hosts
  /etc/localtime
  /etc/nix
  /etc/nsswitch.conf
  /etc/pki
  /etc/resolv.conf
  /etc/ssl
  /etc/static
)
for e in "${RO_ENTRIES[@]}"; do
  append_args --ro-bind-try "$e" "$e"
done

# Add paths as RO
original_ifs="$IFS"
IFS=:
for p in $PATH; do
  if [[ -L "$p" ]]; then
    # Links (only nested?) causes bwrap to crash.
    continue
  elif [[ "$p" = /nix/store/* ]]; then
    # skip nix paths.
    # They are already included
    continue
  elif [[ "$p" = /home/* ]]; then
    # skip home paths.
    # HOME is RO mounted
    continue
  else
    append_args --ro-bind-try "$p" "$p"
  fi
done
IFS=$original_ifs

# add nessesary opencode dirs
OPENCODE_ENTRIES=(
  "$HOME/.cache/opencode"
  "$HOME/.config/opencode"
  "$HOME/.local/share/opencode"
  "$HOME/.local/state/opencode"

  "$HOME/.cache/nix" # for nix develop
)
for e in "${OPENCODE_ENTRIES[@]}"; do
  append_args --bind "$e" "$e"
done

# Add R/W git states for worktrees
if [[ -f "$PROJECT_ROOT/.git" ]]; then
  GITDIR=$(grep gitdir "$PROJECT_ROOT/.git")
  GITDIR=${GITDIR##gitdir: }
  REVGITDIR=$(cat "$GITDIR"/gitdir)
  if [[ "$REVGITDIR" == "$PROJECT_ROOT/.git" ]]; then
    append_args --bind "$GITDIR" "$GITDIR"
  fi
fi

# Parse special arguments (only before first non-@ argument or @@)
while [[ "${1:-}" == @* ]]; do
  case "$1" in
    @net)
      append_args --share-net
      ;;
    @debug-shell)
      DEBUG_MODE=1
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

exec {fd}< "$ARG_PATH"
if [[ "${DEBUG_MODE:-0}" = 0 ]]; then
  exec bwrap --args "$fd" -- "$EXECUTABLE" "$@"
else
  exec bwrap --args "$fd" -- "$SHELL" "$@"
fi
