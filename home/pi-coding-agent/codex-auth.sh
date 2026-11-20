# Runtime paths are set by codex-auth.nix.
if [[ -e /.flatpak-info || -e /run/pi-subagent ]]; then
  echo 'Run pi-codex-auth in a host terminal, not inside Pi.' >&2
  exit 1
fi
umask 077

# Replace the wrapper with the auth process so it owns terminal interrupts.
account_auth() {
  local operation=$1 account=$2 dir
  case "$account" in personal|work) ;; *) return 2 ;; esac
  dir="$state/$account"
  install -d -m 700 "$state" "$dir" || return
  cd "$dir" || return
  export PI_CODING_AGENT_DIR="$dir"
  case "$operation" in
    login) exec "$pi" auth login openai-codex ;;
    logout) exec "$pi" auth logout openai-codex ;;
    status) exec "$pi" auth check --provider openai-codex --no-refresh ;;
  esac
}

image_auth() {
  local dir
  case "$2" in personal|work) ;; *) return 2 ;; esac
  dir="$state/images/$2"
  install -d -m 700 "$state" "$state/images" "$dir" || return
  cd "$dir" || return
  export PI_CODING_AGENT_DIR="$dir"
  exec "$node" "$codex_host" image-auth "$1" "$dir"
}

write_setting() (
  install -d -m 700 "$state" || return
  tmp=$(mktemp "$state/.$1.XXXXXX") || return
  trap 'rm -f -- "$tmp"' EXIT
  printf '%s\n' "$2" > "$tmp" && mv -fT -- "$tmp" "$state/$1"
)

set_image() {
  case "$1" in personal|work|off) ;; *) echo 'Choose work, personal, or off.' >&2; return 2 ;; esac
  write_setting image-account "$1"
}

set_reserve() {
  local value
  value=$(jq -ern --arg value "$1" '$value | tonumber | select(. >= 0 and . <= 100) | tostring' 2>/dev/null) || {
    echo 'Enter a reserve from 0 to 100.' >&2
    return 2
  }
  write_setting reserve "$value"
}

status() {
  local account value=15 image=work
  for account in personal work; do
    printf '%s: ' "$account"
    (account_auth status "$account") || true
  done
  if [[ -f "$state/reserve" ]]; then read -r value < "$state/reserve"; fi
  printf 'Auto personal reserve: %s%%\n' "$value"
  if [[ -f "$state/image-account" ]]; then read -r image < "$state/image-account" || true; fi
  printf 'Images: %s' "$image"
  case "$image" in
    work|personal) printf ' — '; (image_auth status "$image") || true ;;
    *) printf '\n' ;;
  esac
}

if (( $# == 0 )); then
  if [[ -t 0 && -t 1 && "${TERM:-dumb}" != dumb ]]; then
    exec "$node" "$tui" "$0" "$state"
  fi
  status
  exit
fi
case "$1:$#" in
  login:2|logout:2|status:2) account_auth "$1" "$2" ;;
  status:1) status ;;
  reserve:2) set_reserve "$2" ;;
  images:2) set_image "$2" ;;
  image-login:2|image-logout:2|image-status:2) image_auth "${1#image-}" "$2" ;;
  *) echo 'Usage: pi-codex-auth [login|logout|status ACCOUNT | reserve PERCENT | images work|personal|off | image-login|image-logout|image-status ACCOUNT]' >&2; exit 2 ;;
esac
