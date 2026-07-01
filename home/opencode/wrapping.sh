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
  --tmpfs "$HOME"
  --tmpfs /etc
  --tmpfs /run
  --tmpfs /var
  --bind "$PROJECT_ROOT" "$PROJECT_ROOT"
  --clearenv
  --setenv LANG C
  --setenv HOME "$HOME"
  --setenv PWD "$PWD"
)

if [[ -v OPENCODE_CONFIG_CONTENT ]]; then
  append_args --setenv OPENCODE_CONFIG_CONTENT "$OPENCODE_CONFIG_CONTENT"
fi

append_args "${bwrap_args[@]}"

# add nessesary etc dirs
RO_ENTRIES=(
  /bin/sh
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
  /usr/bin/env
)
for e in "${RO_ENTRIES[@]}"; do
  append_args --ro-bind-try "$e" "$e"
done

# Add paths as RO
SANDBOX_PATH=""
original_ifs="$IFS"
IFS=:
for p in $PATH; do
  if [[ -e "$p" ]]; then
    REAL=$(realpath -e "$p")
    SANDBOX_PATH="$SANDBOX_PATH:$REAL"
    append_args --ro-bind-try "$REAL" "$REAL"
  fi
done
IFS=$original_ifs
SANDBOX_PATH=${SANDBOX_PATH%:}
append_args --setenv PATH "$SANDBOX_PATH"

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

# persistant dir
DIR_HASH=$(echo "$PROJECT_ROOT" | sha256sum | cut -F 1)
PERSISTANT_DIR="$HOME"/.local/share/opencode-persistant/"$DIR_HASH"
mkdir -p "$PERSISTANT_DIR"
append_args --bind "$PERSISTANT_DIR" /persistant

# Parse special arguments (only before first non-@ argument or @@)
while [[ "${1:-}" == @* ]]; do
  case "$1" in
    @debug-shell)
      DEBUG_MODE=1
      ;;
    @allow)
      append_args --ro-bind "$2" "$2"
      shift
      ;;
    @allow-rw)
      append_args --bind "$2" "$2"
      shift
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
