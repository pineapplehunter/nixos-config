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

if [[ -z ${XDG_RUNTIME_DIR:-} ]]; then
  echo "XDG_RUNTIME_DIR is not set" >&2
  exit 1
fi
DBUS_PROXY_DIR="$XDG_RUNTIME_DIR/pi-dbus-proxy"
DBUS_PROXY_SOCKET="$DBUS_PROXY_DIR/session-$BASHPID-$RANDOM"
HOST_DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-"unix:path=$XDG_RUNTIME_DIR/bus"}
mkdir -p "$DBUS_PROXY_DIR"
chmod 700 "$DBUS_PROXY_DIR"

PI_WRAPPER_PROFILE=${PI_WRAPPER_PROFILE:-personal}
case "$PI_WRAPPER_PROFILE" in
  personal)
    PI_AGENT_DIR="$HOME/.pi/agent"
    ;;
  work)
    PI_AGENT_DIR="$HOME/.pi/agent-work"
    mkdir -p "$PI_AGENT_DIR"
    chmod 700 "$PI_AGENT_DIR"

    # Share configuration and installed resources while keeping auth.json and
    # other runtime state profile-specific.
    for entry in \
      AGENTS.md APPEND_SYSTEM.md SYSTEM.md \
      extensions skills prompts themes npm git \
      settings.json keybindings.json models.json trust.json pi-usage.json
    do
      source_path="$HOME/.pi/agent/$entry"
      profile_path="$PI_AGENT_DIR/$entry"
      if [[ -e "$source_path" && ! -e "$profile_path" && ! -L "$profile_path" ]]; then
        ln -s "$source_path" "$profile_path"
      fi
    done
    ;;
  *)
    echo "Unknown Pi wrapper profile: $PI_WRAPPER_PROFILE" >&2
    exit 1
    ;;
esac

xdg-dbus-proxy \
  "$HOST_DBUS_SESSION_BUS_ADDRESS" \
  "$DBUS_PROXY_SOCKET" \
  --filter \
  --call=io.github.pineapplehunter.LocalNotify1=io.github.pineapplehunter.LocalNotify1.Notify@/io/github/pineapplehunter/LocalNotify1 &
DBUS_PROXY_PID=$!
# Invoked by the EXIT trap below.
# shellcheck disable=SC2329
cleanup_dbus_proxy() {
  kill "$DBUS_PROXY_PID" 2> /dev/null || true
  wait "$DBUS_PROXY_PID" 2> /dev/null || true
  rm -f "$DBUS_PROXY_SOCKET"
}
trap cleanup_dbus_proxy EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

for _ in $(seq 1 100); do
  [[ -S "$DBUS_PROXY_SOCKET" ]] && break
  if ! kill -0 "$DBUS_PROXY_PID" 2> /dev/null; then
    echo "Failed to start the D-Bus proxy" >&2
    exit 1
  fi
  sleep 0.01
done
if [[ ! -S "$DBUS_PROXY_SOCKET" ]]; then
  echo "Timed out waiting for the D-Bus proxy" >&2
  exit 1
fi

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
  --dir /run/user
  --dir "$XDG_RUNTIME_DIR"
  --ro-bind "$DBUS_PROXY_SOCKET" "$XDG_RUNTIME_DIR/bus"
  --tmpfs /var
  --bind "$HOME/.pi" "$HOME/.pi"
  --bind "$HOME/.cache/nix" "$HOME/.cache/nix"
  --bind "$PROJECT_ROOT" "$PROJECT_ROOT"
  --clearenv
  --setenv LANG C
  --setenv HOME "$HOME"
  --setenv PWD "$PWD"
  --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR"
  --setenv DBUS_SESSION_BUS_ADDRESS "unix:path=$XDG_RUNTIME_DIR/bus"
  --setenv PI_CODING_AGENT_DIR "$PI_AGENT_DIR"
  --setenv PI_CODING_AGENT_SESSION_DIR "$HOME/.pi/agent/sessions"
  --setenv PI_WRAPPER_PROFILE "$PI_WRAPPER_PROFILE"
  --setenv PUEUE_CONFIG_PATH "$PUEUE_CONFIG_PATH"
  --setenv GIT_AUTHOR_NAME 'pi-coding-agent'
  --setenv GIT_AUTHOR_EMAIL 'peshogo+agent@gmail.com'
  --setenv GIT_COMMITTER_NAME 'pi-coding-agent'
  --setenv GIT_COMMITTER_EMAIL 'peshogo+agent@gmail.com'
  --setenv EDITOR hx
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

# Persistent per-project temporary directory. Keep it visible at its host path
# as well as /tmp so a nested pi wrapper resolves and reuses the same directory.
DIR_HASH=$(echo "$PROJECT_ROOT" | sha256sum | cut -F 1)
SANDBOX_TMP_DIR="$HOME"/.local/share/pi-tmp/"$DIR_HASH"
mkdir -p "$SANDBOX_TMP_DIR"
chmod 700 "$SANDBOX_TMP_DIR"
append_args \
  --bind "$SANDBOX_TMP_DIR" "$SANDBOX_TMP_DIR" \
  --bind "$SANDBOX_TMP_DIR" /tmp

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
status=0
if [[ "${DEBUG_MODE:-0}" = 0 ]]; then
  bwrap --args "$fd" -- "$EXECUTABLE" "$@" || status=$?
else
  bwrap --args "$fd" -- "$SHELL" "$@" || status=$?
fi
exit "$status"
