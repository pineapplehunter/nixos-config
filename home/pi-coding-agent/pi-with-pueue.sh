set -euo pipefail

mkdir -p /tmp/pi-pueue
chmod 700 /tmp/pi-pueue

if ! pueue status >/dev/null 2>&1; then
  rm -f /tmp/pi-pueue/pueue.pid /tmp/pi-pueue/pueue.socket
  pueued -d
  for _ in $(seq 1 50); do
    pueue status >/dev/null 2>&1 && break
    sleep 0.1
  done
fi

exec @PI_EXECUTABLE@ "$@"
