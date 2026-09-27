#!/usr/bin/env bash
# Observe Avahi records on the host network before, during and after the
# appliance runs. The shared printing base supplies avahi-printing and PAPPL
# publishes printer queues; the appliance must not publish Avahi's sample
# SSH/SFTP records.
set -euo pipefail

image="${IMAGE:-ghcr.io/projectbluefin/ps-printer-app:build}"
runtime="${RUNTIME:-podman}"
port="${PORT:-18064}"
suffix="$(printf '%04x' "$((RANDOM % 65536))")"
names=("ps-adv-${suffix}-a" "ps-adv-${suffix}-b")
queues=("ps-adv-${suffix}-a" "ps-adv-${suffix}-b")
evidence="${EVIDENCE_DIR:-$(mktemp -d)}"
mkdir -p "$evidence"
state_root="$(mktemp -d)"
containers=()

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local name
  for name in "${containers[@]}"; do
    "$runtime" logs "$name" >"$evidence/$name.log" 2>&1 || true
    "$runtime" rm -f "$name" >/dev/null 2>&1 || true
  done
  "$runtime" unshare rm -rf "$state_root" >/dev/null 2>&1 || rm -rf "$state_root"
}
trap cleanup EXIT

for command in "$runtime" avahi-browse timeout curl; do
  command -v "$command" >/dev/null 2>&1 || fail "required tool not found: $command"
done
"$runtime" image inspect "$image" >"$evidence/image.json" || fail "image $image not found; build the image first"
"$runtime" run --rm --entrypoint /usr/bin/bash "$image" -ec '
  test ! -e /etc/avahi/services/ssh.service
  test ! -e /etc/avahi/services/sftp-ssh.service
' || fail "the image contains an Avahi sample SSH or SFTP service record"

snapshot() {
  local phase="$1" service
  for service in _ssh._tcp _sftp-ssh._tcp _ipp._tcp; do
    timeout 30 avahi-browse --resolve --terminate --parsable "$service" \
      >"$evidence/$phase.$service" || fail "could not browse $service for $phase"
  done
}

remote_records() {
  # Ignore interface/protocol duplication, retain the advertised identity,
  # host, address and port so unrelated LAN records can be compared exactly.
  awk -F ';' '$1 == "=" {print $4 ";" $5 ";" $6 ";" $7 ";" $8 ";" $9}' "$1" | LC_ALL=C sort -u
}

check_remote_records() {
  local phase="$1" service
  for service in _ssh._tcp _sftp-ssh._tcp; do
    diff -u <(remote_records "$evidence/before.$service") \
      <(remote_records "$evidence/$phase.$service") ||
      fail "$service records changed during $phase"
  done
}

queues_present() {
  local phase="$1" index
  for index in 0 1; do
    awk -F ';' -v expected_port="$((port + index))" -v queue="${queues[index]}" '
      $1 == "=" && $5 == "_ipp._tcp" && $9 == expected_port &&
        index($0, "rp=ipp/print/" queue) {found=1}
      END {exit !found}
    ' "$evidence/$phase._ipp._tcp" || return 1
  done
}

wait_for_http() {
  local target_port="$1" name="$2"
  for _ in $(seq 1 90); do
    if curl --fail --silent "http://127.0.0.1:${target_port}/" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  "$runtime" logs "$name" >&2 || true
  return 1
}

wait_for_queues() {
  local phase="$1"
  for _ in $(seq 1 30); do
    snapshot "$phase"
    queues_present "$phase" && return 0
    sleep 1
  done
  return 1
}

echo '== Existing remote-login records before the appliance starts =='
snapshot before

for index in 0 1; do
  port_for_instance="$((port + index))"
  state_dir="$state_root/$index"
  mkdir "$state_dir"
  "$runtime" unshare chown 65532:65532 "$state_dir"
  containers+=("${names[index]}")
  "$runtime" run -d --name "${names[index]}" --network host \
    -e "PORT=$port_for_instance" \
    -e "PRINTER_APP_INSTANCE=${names[index]}" \
    -v "$state_dir:/var/lib/ps-printer-app:Z" "$image" >/dev/null
  wait_for_http "$port_for_instance" "${names[index]}" ||
    fail "${names[index]} did not become ready on port $port_for_instance"
  "$runtime" exec "${names[index]}" /usr/bin/ps-printer-app \
    -u "ipp://127.0.0.1:${port_for_instance}/ipp/system" \
    -d "${queues[index]}" \
    -m generic \
    -v 'cups:socket://127.0.0.1:19999' add ||
    fail "could not add IPP queue ${queues[index]}"
done

sleep 5
wait_for_queues started || fail 'both instance IPP queues did not resolve after startup'
check_remote_records started
echo '  ok: both IPP queues resolve on their own ports; SSH/SFTP records are unchanged'

"$runtime" restart --time 15 "${names[0]}" >/dev/null
wait_for_http "$port" "${names[0]}" || fail "${names[0]} did not become ready after restart"
sleep 5
snapshot restarted
queues_present restarted || fail 'both instance IPP queues did not resolve after restart'
check_remote_records restarted

echo 'PASS: the image advertises no sample SSH/SFTP records and both IPP queues remain discoverable after startup and restart.'
printf 'Evidence: %s\nNo physical discovery or printed paper was tested.\n' "$evidence"
