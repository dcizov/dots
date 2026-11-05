#!/usr/bin/env bash
# Remove a stale pacman database lock — and refuse to when it is not stale.
#
#   sudo ucli fix lock            remove /var/lib/pacman/db.lck if nothing holds it
#   sudo ucli fix lock --dry-run  report only
#
# `db.lck` is how pacman serialises database access. It is left behind by a
# pacman that was killed (Ctrl-C during a download, a crash, a full disk), and
# then every later `pacman -S` says:
#
#   error: failed to init transaction (unable to lock database)
#
# Deleting it while a pacman *is* running corrupts the database, so this checks
# first: an open handle on the file (fuser), or a running pacman/AUR-helper process,
# means "not stale — wait" and exit 1.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

dry_run=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) dry_run=1 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# UCLI_TEST_ROOT is the test seam (setup-boot.sh has the same idea): with it
# set, the root check is skipped so the logic can be exercised on a temp tree.
if (( EUID != 0 )) && [[ -z "${UCLI_TEST_ROOT:-}" ]]; then
  echo "Run as root: sudo ucli fix lock" >&2
  exit 1
fi

lock="${UCLI_TEST_ROOT:-}/var/lib/pacman/db.lck"

ui_rule "pacman lock"
if [[ ! -e "$lock" ]]; then
  printf '  %s is not there — nothing to do\n' "$lock"
  exit 0
fi

# An open file handle is the authoritative answer: pacman holds db.lck open for
# the whole transaction, so fuser sees it.
in_use=""
if command -v fuser >/dev/null 2>&1; then
  if fuser "$lock" >/dev/null 2>&1; then in_use="fuser"; fi
fi
if [[ -z "$in_use" ]]; then
  for proc in pacman paru shelly shelly-ui; do
    if pgrep -x "$proc" >/dev/null 2>&1; then in_use="$proc"; break; fi
  done
fi

if [[ -n "$in_use" ]]; then
  if [[ "$in_use" == fuser ]]; then
    ui_fail "the lock is in use (something has the file open)"
  else
    ui_fail "the lock is in use ($in_use is running)"
  fi
  printf '  wait for it to finish; removing it now can corrupt the database.\n'
  printf '  if you are sure it is hung: sudo systemctl reboot\n'
  exit 1
fi

printf '  %s exists and nothing holds it (stale after a killed pacman)\n' "$lock"
if (( dry_run )); then
  printf '+ rm -f %q\n' "$lock"
  exit 0
fi
rm -f "$lock"
ui_ok "removed $lock"
printf '  retry your pacman command.\n'
