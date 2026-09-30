set -euo pipefail

export PI_PUEUE_NOTIFY_DIR=/run/pi-pueue
mkdir -p "$PI_PUEUE_NOTIFY_DIR/completions"
chmod 700 "$PI_PUEUE_NOTIFY_DIR" "$PI_PUEUE_NOTIFY_DIR/completions"

if ! pueue status >/dev/null 2>&1; then
  rm -f /run/pi-pueue/pueue.pid /run/pi-pueue/pueue.socket
  pueued -d
  for _ in $(seq 1 50); do
    pueue status >/dev/null 2>&1 && break
    sleep 0.1
  done
fi

exec @PI_EXECUTABLE@ "$@"
