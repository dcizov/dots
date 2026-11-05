#!/usr/bin/env bash
# Remove orphaned packages: installed as dependencies, no longer required by
# anything.
#
#   sudo ucli fix orphans               list them, ask, remove with -Rns
#   sudo ucli fix orphans --yes         no question (what the timer/wrapper uses)
#   sudo ucli fix orphans --dry-run     list only, change nothing
#
# `pacman -Qtdq` is the authoritative list ("dependencies that nothing requires").
# Removal is `-Rns` so their own unneeded dependencies and now-empty config
# directories go too, in one transaction. A Snapper snapshot is NOT taken: this is
# the same class of change as `pacman -Rns` in a normal upgrade, and snap-pac
# already snapshots pacman transactions. Use `ucli snapshot` first if you want a
# named restore point.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

yes_flag=0
dry_run=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) yes_flag=1 ;;
    --dry-run|-n) dry_run=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# UCLI_TEST_ROOT is the test seam (setup-boot.sh has the same idea): with it
# set, the root check is skipped so the logic can be exercised on a temp tree.
if (( EUID != 0 )) && [[ -z "${UCLI_TEST_ROOT:-}" ]]; then
  echo "Run as root: sudo ucli fix orphans" >&2
  exit 1
fi

ui_rule "orphaned packages"
mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)

if (( ${#orphans[@]} == 0 )); then
  printf '  none — every installed dependency is still required\n'
  exit 0
fi

printf '  %s orphan(s):\n' "${#orphans[@]}"
printf '    %s\n' "${orphans[@]}"

if (( dry_run )); then
  printf '+ pacman -Rns --noconfirm %s\n' "${orphans[*]}"
  exit 0
fi

if (( ! yes_flag )) && [[ -t 0 ]]; then
  ui_confirm "Remove these ${#orphans[@]} package(s)?" || { echo "aborted."; exit 1; }
fi

pacman -Rns --noconfirm "${orphans[@]}"
ui_ok "removed ${#orphans[@]} orphan(s)"
