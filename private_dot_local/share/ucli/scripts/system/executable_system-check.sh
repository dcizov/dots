#!/usr/bin/env bash
# Machine facts: OS, kernel, desktop, CPU, memory, root filesystem (btrfs
# subvolumes included) and firmware. `ucli profile` shows what ucli itself
# configured; this shows what the machine actually is. Read-only, no sudo —
# the btrfs subvolume count is the only root-read and it is skipped when the
# sudo timestamp is cold.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh
. "$script_dir/../lib/ui.sh"

field() { printf '  %-13s %s\n' "$1" "$2"; }

ui_rule "os"
field distro "$(. /etc/os-release && printf '%s %s' "$NAME" "$VERSION_ID")"
field kernel "$(uname -r)"
field arch "$(uname -m)"
field desktop "${XDG_CURRENT_DESKTOP:-(console)}"
field session "${XDG_SESSION_TYPE:-tty}"

ui_rule "cpu and memory"
field cpu "$(grep -m1 'model name' /proc/cpuinfo | awk -F': ' '{ print $2 }')"
field cores "$(nproc)"
field memory "$(awk '/^MemTotal:/ { printf "%.1f GiB\n", $2 / 1048576 }' /proc/meminfo)"

ui_rule "root filesystem"
root_fs="$(findmnt -no FSTYPE /)"
field type "$root_fs"
field device "$(findmnt -no SOURCE /)"
field options "$(findmnt -no OPTIONS /)"
if [[ "$root_fs" == btrfs ]]; then
  if sudo -n true 2>/dev/null; then
    field subvolumes "$(sudo -n btrfs subvolume list / | grep -c .) (sudo btrfs subvolume list /)"
  else
    field subvolumes "unknown (sudo btrfs subvolume list /)"
  fi
fi

ui_rule "firmware"
# /sys/class/dmi/id is world-readable: no dmidecode, no sudo. dmidecode is only
# a fallback for kernels built without dmi-id.
dmi=/sys/class/dmi/id
if [[ -d "$dmi" ]]; then
  while IFS='|' read -r key label; do
    [[ -r "$dmi/$key" ]] || continue
    field "$label" "$(cat "$dmi/$key")"
  done <<'PAIRS'
sys_vendor|vendor
product_name|product
product_version|version
board_name|board
bios_vendor|bios
bios_version|bios version
bios_date|bios date
PAIRS
else
  field firmware "dmi-id not available (no /sys/class/dmi/id)"
fi
if [[ -d /sys/firmware/efi ]]; then
  field boot "UEFI (ucli bios reboots into the setup screen)"
else
  field boot "legacy BIOS"
fi
printf '\n'
