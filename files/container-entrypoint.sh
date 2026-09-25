#!/usr/bin/env bash
set -euo pipefail

port="${PORT:-18020}"
if [[ ! "$port" =~ ^[0-9]+$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
  printf 'PORT must be an integer from 1 to 65535\n' >&2
  exit 64
fi

state_dir=/var/lib/ps-printer-app
mkdir -p "$state_dir/ppd" "$state_dir/spool" "$state_dir/usb" "$state_dir/cups/ssl" /run/dbus /run/avahi-daemon /run/ps-printer-app
if [[ ! -e "$state_dir/cups/snmp.conf" ]]; then
  cp /etc/cups/snmp.conf "$state_dir/cups/snmp.conf"
fi
for quirk in /usr/share/cups/usb/*.usb-quirks /usr/lib/cups/backend/*.usb-quirks; do
  [[ -f "$quirk" ]] || continue
  cp -n "$quirk" "$state_dir/usb/"
done

export BACKEND_DIR=/usr/lib/ps-printer-app/backend
export CUPS_SERVERBIN=/usr/lib/ps-printer-app
export CUPS_SERVERROOT="$state_dir/cups"
export FILTER_DIR=/usr/lib/ps-printer-app/filter
export PATH="$FILTER_DIR:$PATH"
export PPDC_DATADIR=/usr/share/ppdc
export PPD_PATHS="/usr/share/ppd/:$state_dir/ppd/"
export SPOOL_DIR="$state_dir/spool"
export STATE_DIR="$state_dir"
export STATE_FILE="$state_dir/ps-printer-app.state"
export TESTPAGE_DIR=/usr/share/ps-printer-app
export TMPDIR=/tmp
export USB_QUIRK_DIR="$state_dir"

children=()
stop_children() {
  local index pid
  for ((index = ${#children[@]} - 1; index >= 0; index--)); do
    pid="${children[index]}"
    kill -TERM "$pid" 2>/dev/null || true
  done
  wait "${children[@]}" 2>/dev/null || true
}
handle_signal() {
  trap - TERM INT EXIT
  stop_children
  exit 143
}
trap handle_signal TERM INT
trap stop_children EXIT

dbus-daemon --system --nofork --nopidfile &
children+=("$!")
for _ in $(seq 1 30); do
  [[ -S /run/dbus/system_bus_socket ]] && break
  sleep 0.1
done
[[ -S /run/dbus/system_bus_socket ]]

avahi-daemon --no-drop-root --no-chroot &
children+=("$!")
for _ in $(seq 1 30); do
  [[ -f /run/avahi-daemon/pid ]] && break
  sleep 0.1
done
[[ -f /run/avahi-daemon/pid ]]

ps-printer-app -o "log-file=$state_dir/ps-printer-app.log" -o "server-port=$port" server &
children+=("$!")

if wait -n "${children[@]}"; then
  status=1
else
  status=$?
fi
stop_children
trap - TERM INT EXIT
exit "$status"
