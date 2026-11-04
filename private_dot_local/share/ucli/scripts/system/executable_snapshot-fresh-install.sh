#!/usr/bin/env bash
# Take a Snapper snapshot. This is the only implementation in the repo: every
# restore point goes through it.
#
#   sudo snapshot-fresh-install.sh [--yes] [--dry-run] [--no-snapshot] [DESCRIPTION]
#
# Callers:
#   ucli snapshot                        standalone, any description
#   install.sh                           after the bootstrap ("post-bootstrap")
#   ucli setup-system (install-profile)  before it starts ("before setup-system")
#   setup-desktop.sh                     "<DE> Setup", before it snapshots
#   arch-snapper-limine.sh               snapshot #1 ("Fresh Arch Linux Installation")
#   debloat-desktop.sh / uninstall.sh    before they remove anything
#
# Flags:
#   --no-snapshot     skip and exit 0. Also honoured as UCLI_NO_SNAPSHOT=1, so one
#                     environment variable turns off every restore point in a run.
#   --dry-run         print what would happen, change nothing
#   --yes / -y        no questions (there are none today; kept for symmetry)
#
# Exit status: 0 when a snapshot was taken *and* when there is nothing to
# snapshot (no snapper, or no /etc/snapper/configs/root — say so and move on, so a
# caller can always continue). A real snapper failure still exits non-zero.
set -euo pipefail

description="Fresh Arch Linux Installation"
take_snapshot=1
dry_run=0

while (($#)); do
  case "$1" in
    --no-snapshot) take_snapshot=0 ;;
    --dry-run|-n) dry_run=1 ;;
    --yes|-y) ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) description="$1" ;;
  esac
  shift
done

if [[ "${UCLI_NO_SNAPSHOT:-0}" == "1" ]]; then
  take_snapshot=0
fi

if (( ! take_snapshot )); then
  echo "snapshot skipped (--no-snapshot / UCLI_NO_SNAPSHOT=1)"
  exit 0
fi

if (( EUID != 0 )); then
  echo "Run as root: sudo $0 <description>" >&2
  exit 1
fi

# Not applicable vs failed: without snapper there is nothing to snapshot, and no
# caller should die over a missing restore point.
if ! command -v snapper >/dev/null 2>&1; then
  echo "note: snapper is not installed, so no snapshot was taken"
  echo "      'ucli setup-snapshots' sets up snapper + limine (btrfs root only)"
  exit 0
fi

if [[ ! -f /etc/snapper/configs/root ]]; then
  echo "note: no snapper root config (/etc/snapper/configs/root), so no snapshot was taken"
  echo "      run 'ucli setup-snapshots' once; on CachyOS the installer already did"
  exit 0
fi

# A snapshot of a non-btrfs root would fail inside snapper with a worse message.
if [[ "$(findmnt -no FSTYPE / 2>/dev/null || echo unknown)" != btrfs ]]; then
  echo "note: / is not btrfs, so there is nothing for snapper to snapshot"
  exit 0
fi

if (( dry_run )); then
  echo "+ snapper --no-dbus -c root create --description $(printf '%q' "$description") --userdata important=yes"
  echo "+ record the snapshot number in /etc/ucli/installation-snapshot"
  exit 0
fi

snap_id="$(snapper --no-dbus -c root create --print-number \
  --description "$description" \
  --userdata "important=yes")"

mkdir -p /etc/ucli
echo "$snap_id" >/etc/ucli/installation-snapshot

echo "Created snapshot ($snap_id): $description"

# limine-snapper-sync writes the new snapshot into the boot menu; absent on
# non-Limine installs, so it is best effort.
if command -v limine-snapper-sync >/dev/null 2>&1; then
  limine-snapper-sync || true
fi
