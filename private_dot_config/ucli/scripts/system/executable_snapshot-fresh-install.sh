#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

if ! command -v snapper >/dev/null 2>&1; then
  echo "snapper is not installed" >&2
  exit 1
fi

if [[ ! -f /etc/snapper/configs/root ]]; then
  echo "snapper root config not found" >&2
  exit 1
fi

SNAP_ID=$(snapper --no-dbus -c root create --print-number \
  --description "Fresh Arch Linux Installation" \
  --userdata "important=yes")

mkdir -p /etc/ucli
echo "$SNAP_ID" > /etc/ucli/installation-snapshot

echo "Created fresh-install snapshot: $SNAP_ID"

if command -v limine-snapper-sync >/dev/null 2>&1; then
  limine-snapper-sync || true
fi
