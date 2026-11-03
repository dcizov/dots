#!/usr/bin/env bash
set -euo pipefail

echo "== os-release =="
cat /etc/os-release | sed -n '1,8p'

echo
printf 'CPU vendor: '
grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}' || true

echo
printf 'Root fs: '
findmnt -no FSTYPE /
printf 'Root source: '
findmnt -no SOURCE /
printf 'Root options: '
findmnt -no OPTIONS /

echo
if [[ "$(findmnt -no FSTYPE /)" == btrfs ]]; then
  echo "== btrfs subvolumes =="
  sudo btrfs subvolume list / | sed -n '1,80p'
else
  echo "root is not btrfs"
fi

echo
if command -v snapper >/dev/null 2>&1; then
  echo "== snapper configs =="
  sudo snapper list-configs || true
fi

echo
if command -v limine-snapper-info >/dev/null 2>&1; then
  echo "== limine snapper info =="
  sudo limine-snapper-info || true
fi
