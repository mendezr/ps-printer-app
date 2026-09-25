#!/usr/bin/env bash
set -euo pipefail

cups_target='ghostscript-fsdk.bst:freedesktop-sdk.bst:components/_private/cups-base.bst'
source_dir='.bst/ps-cups-patch-chain-source'

deps="$(just bst show --deps all --format '%{name}' oci/ps-printer-app.bst)"
count="$(grep -cxF "$cups_target" <<< "$deps" || true)"
if [[ "$count" -ne 1 ]]; then
  printf 'FAIL: expected exactly one FSDK CUPS base, found %s\n' "$count" >&2
  exit 1
fi

mkdir -p .bst
rm -rf "$source_dir"
trap 'rm -rf "$source_dir"' EXIT
just bst source checkout --force --directory "$source_dir" "$cups_target"
printf 'OK: one FSDK CUPS provider and its canonical patches apply cleanly\n'
