#!/usr/bin/env bash
set -euo pipefail

description="Fresh Arch Linux Installation"
if [ $# -ge 1 ]; then
  description="$1"
fi

if (( EUID != 0 )); then
  echo "Run as root: sudo $0 <description>" >&2
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
  --description "$description" \
  --userdata "important=yes")

mkdir -p /etc/ucli
echo "$SNAP_ID" > /etc/ucli/installation-snapshot

echo "Created snapshot ($SNAP_ID): $description"

if command -v limine-snapper-sync >/dev/null 2>&1; then
  limine-snapper-sync || true
fi
