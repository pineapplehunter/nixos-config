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

mkdir -p "$HOME/.pi" "$HOME/.cache/nix"

bwrap_args=(
  --unshare-all
  --die-with-parent
  --cap-drop ALL
  --share-net
  --dev /dev
  --proc /proc
  --ro-bind /nix /nix
  --tmpfs "$HOME"
  --tmpfs /etc
  --tmpfs /run
  --tmpfs /var
  --bind "$HOME/.pi" "$HOME/.pi"
  --bind "$HOME/.cache/nix" "$HOME/.cache/nix"
  --bind "$PROJECT_ROOT" "$PROJECT_ROOT"
  --clearenv
  --setenv LANG C
  --setenv HOME "$HOME"
  --setenv PWD "$PWD"
)

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

# Add R/W git states for worktrees
if [[ -f "$PROJECT_ROOT/.git" ]]; then
  GITDIR=$(grep gitdir "$PROJECT_ROOT/.git")
  GITDIR=${GITDIR##gitdir: }
  COMMON_PATH=$(cat "$GITDIR/commondir")
  GITDIR=$(realpath "$COMMON_PATH")
  append_args --bind "$GITDIR" "$GITDIR"
fi

# Persistent per-project temporary directory. This is mounted as /tmp inside the
# sandbox so normal tooling defaults survive across pi restarts.
DIR_HASH=$(echo "$PROJECT_ROOT" | sha256sum | cut -F 1)
SANDBOX_TMP_DIR="$HOME"/.local/share/pi-tmp/"$DIR_HASH"
mkdir -p "$SANDBOX_TMP_DIR"
chmod 700 "$SANDBOX_TMP_DIR"
append_args --bind "$SANDBOX_TMP_DIR" /tmp

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
