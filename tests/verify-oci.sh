#!/usr/bin/env bash
set -euo pipefail

image='ghcr.io/projectbluefin/ps-printer-app:build'
name='ps-printer-app-smoke'
other='ps-printer-app-isolated'
invalid='ps-printer-app-invalid-port'
port="${PORT:-18180}"
other_port="$((port + 1))"
sink_port="$((port + 1000))"
state_dir="$(mktemp -d)"
other_state_dir="$(mktemp -d)"
output_file="$(mktemp)"
cookie_file="$(mktemp)"
sink_pid=''

cleanup() {
  podman rm -f "$name" "$other" "$invalid" >/dev/null 2>&1 || true
  if [[ -n "$sink_pid" ]]; then
    kill "$sink_pid" >/dev/null 2>&1 || true
    wait "$sink_pid" 2>/dev/null || true
  fi
  podman unshare rm -rf "$state_dir" "$other_state_dir"
  rm -f "$output_file" "$cookie_file"
}
trap cleanup EXIT

wait_for_service() {
  local target_port="$1" http https
  for _ in $(seq 1 60); do
    http="$(curl --fail --silent "http://127.0.0.1:${target_port}/" 2>/dev/null || true)"
    https="$(curl --insecure --fail --silent "https://127.0.0.1:${target_port}/" 2>/dev/null || true)"
    if [[ "$http" == *'<title>PostScript Printer Application</title>'* &&
          "$https" == *'<title>PostScript Printer Application</title>'* ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

podman run --rm --entrypoint /usr/bin/bash "$image" -c '
  set -euo pipefail
  test "$(id -u):$(id -g)" = 65532:65532
  test "$(id -un)" = nonroot
  test "$(readlink /usr/lib/ps-printer-app)" = /usr/lib/cups
  test -f /usr/share/ps-printer-app/testpage.pdf
  test -f /usr/share/ppd/generic-ps-printer.ppd
  test -s /usr/share/cups/usb/org.cups.usb-quirks
  for executable in \
    /usr/bin/ps-printer-app /usr/bin/gs \
    /usr/lib/cups/backend/socket /usr/lib/cups/backend/dnssd \
    /usr/lib/cups/backend/ipp /usr/lib/cups/backend/ipps \
    /usr/lib/cups/backend/lpd /usr/lib/cups/backend/snmp \
    /usr/lib/cups/backend/usb /usr/lib/cups/filter/foomatic-rip \
    /usr/lib/cups/filter/pdftops /usr/lib/cups/filter/hpps; do
    test -x "$executable"
    dependencies="$(ldd "$executable")"
    [[ "$dependencies" != *"not found"* ]]
  done
  for archive in foomatic-ps-ppds hplip-ps-ppds; do
    test -x "/usr/share/ppd/$archive"
    entries="$("/usr/share/ppd/$archive" list)"
    [[ -n "$entries" ]]
  done
  for tool in apt apk dnf rpm pip cc gcc make cmake pkg-config; do
    ! command -v "$tool" >/dev/null 2>&1
  done
'
version="$(< VERSION)"
[[ "$(podman run --rm --entrypoint /usr/bin/ps-printer-app "$image" --version)" == "$version" ]]
[[ "$(podman image inspect "$image" --format '{{.Config.User}}')" == '65532:65532' ]]
[[ "$(podman image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.version"}}')" == "$version" ]]

chmod 0777 "$state_dir" "$other_state_dir"
python3 tests/socket-sink.py "$sink_port" "$output_file" &
sink_pid=$!

podman run -d --name "$name" --network host -e PORT="$port" \
  -v "$state_dir:/var/lib/ps-printer-app:Z" "$image" >/dev/null
wait_for_service "$port" || { podman logs "$name" >&2; exit 1; }
podman exec "$name" test -s /var/lib/ps-printer-app/usb/org.cups.usb-quirks

# This is the user-facing PPD upload form, not a hand-copied file in a volume.
form="$(curl --insecure --fail --silent --show-error --cookie-jar "$cookie_file" \
  "https://127.0.0.1:${port}/addppd")"
session="${form#*name=\"session\" value=\"}"
session="${session%%\"*}"
[[ -n "$session" && "$session" != "$form" ]]
response="$(curl --insecure --fail --silent --show-error --cookie "$cookie_file" \
  -F "session=$session" -F "action=add-ppdfiles" \
  -F 'ppdfiles=@generic-ps-printer.ppd;filename=user-test.ppd' \
  "https://127.0.0.1:${port}/addppd")"
[[ "$response" == *'user-test.ppd'* && "$response" == *'Uploaded:'* ]]
podman exec "$name" /usr/bin/bash -c \
  'test "$(< /var/lib/ps-printer-app/ppd/user-test.ppd)" == "$(< /usr/share/ppd/generic-ps-printer.ppd)"'

system_uri="ipp://127.0.0.1:${port}/ipp/system"
printer_uri="ipp://127.0.0.1:${port}/ipp/print/ps-test"
podman exec "$name" ps-printer-app -u "$system_uri" -d ps-test -m generic--postscript-printer--en \
  -v "cups:socket://127.0.0.1:${sink_port}" add
printer_page="$(curl --fail --silent --show-error --cookie-jar "$cookie_file" \
  "http://127.0.0.1:${port}/ps-test/")"
session="${printer_page#*name=\"session\" value=\"}"
session="${session%%\"*}"
[[ -n "$session" && "$session" != "$printer_page" ]]
curl --fail --silent --show-error --cookie "$cookie_file" \
  --data-urlencode "session=$session" --data 'action=print-test-page' \
  "http://127.0.0.1:${port}/ps-test/" >/dev/null

for _ in $(seq 1 120); do
  [[ -s "$output_file" ]] && break
  sleep 0.5
done
if [[ ! -s "$output_file" ]]; then
  podman exec "$name" ps-printer-app -u "$printer_uri" jobs >&2 || true
  podman logs "$name" >&2
  printf 'FAIL: no PostScript reached the CUPS socket backend\n' >&2
  exit 1
fi
wait "$sink_pid"
sink_pid=''
python3 - "$output_file" <<'PY'
from pathlib import Path
import sys

output = Path(sys.argv[1]).read_bytes()
assert b"%!PS" in output[:256], "socket output lacks the PostScript header"
assert b"%%Page:" in output, "socket output has no PostScript page"
PY

jobs=''
for _ in $(seq 1 120); do
  jobs="$(podman exec "$name" ps-printer-app -u "$printer_uri" jobs)"
  [[ "$jobs" == *'completed'* ]] && break
  sleep 0.5
done
[[ "$jobs" == *'completed'* ]]
podman exec "$name" /usr/bin/bash -c \
  'printf "%s\n" "# preserved" > /var/lib/ps-printer-app/cups/snmp.conf'

# Distinct volumes/ports cannot see each other's configured printers or PPDs.
podman run -d --name "$other" --network host -e PORT="$other_port" \
  -v "$other_state_dir:/var/lib/ps-printer-app:Z" "$image" >/dev/null
wait_for_service "$other_port" || { podman logs "$other" >&2; exit 1; }
! podman exec "$other" ps-printer-app \
  -u "ipp://127.0.0.1:${other_port}/ipp/system" printers | grep -q ps-test
podman exec "$other" test ! -e /var/lib/ps-printer-app/ppd/user-test.ppd
podman stop --time 15 "$other" >/dev/null
podman rm "$other" >/dev/null

podman stop --time 15 "$name" >/dev/null
read -r running exit_status <<< "$(podman inspect "$name" --format '{{.State.Running}} {{.State.ExitCode}}')"
[[ "$running" == false && "$exit_status" -eq 143 ]]
podman rm "$name" >/dev/null

podman run -d --name "$name" --network host -e PORT="$port" \
  -v "$state_dir:/var/lib/ps-printer-app:Z" "$image" >/dev/null
wait_for_service "$port" || { podman logs "$name" >&2; exit 1; }
podman exec "$name" /usr/bin/bash -c '
  test "$(< /var/lib/ps-printer-app/cups/snmp.conf)" = "# preserved"
  test -s /var/lib/ps-printer-app/ppd/user-test.ppd
  test -s /var/lib/ps-printer-app/ps-printer-app.state
'
podman exec "$name" ps-printer-app -u "$system_uri" printers | grep -q ps-test
curl --insecure --fail --silent --show-error "https://127.0.0.1:${port}/addppd" | grep -q user-test.ppd

# Loss of a required child must terminate the container, not leave stale IPP.
podman exec "$name" /usr/bin/bash -c '
  for proc in /proc/[0-9]*; do
    read -r comm < "$proc/comm" || continue
    if [[ "$comm" == avahi-daemon ]]; then
      kill -TERM "${proc##*/}"
      exit 0
    fi
  done
  exit 1
'
for _ in $(seq 1 150); do
  running="$(podman inspect "$name" --format '{{.State.Running}}')"
  [[ "$running" == false ]] && break
  sleep 0.1
done
read -r running exit_status <<< "$(podman inspect "$name" --format '{{.State.Running}} {{.State.ExitCode}}')"
[[ "$running" == false && "$exit_status" -ne 0 ]]

set +e
podman run --name "$invalid" -e PORT=invalid "$image" >/dev/null 2>&1
invalid_status=$?
set -e
[[ "$invalid_status" -eq 64 ]]
printf 'OK: FSDK PS appliance, real PostScript sink, user PPD, persistence and supervision\n'
