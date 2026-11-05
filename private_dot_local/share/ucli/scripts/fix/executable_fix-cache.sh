#!/usr/bin/env bash
# Reclaim disk space the safe way: the package cache and the journal.
#
#   sudo ucli fix cache                keep the 2 newest versions of each package
#   sudo ucli fix cache --keep 1       keep only the installed version
#   sudo ucli fix cache --dry-run      show the sizes, change nothing
#
# What it does NOT touch: the AUR build caches (~/.cache/paru, ~/.cache/shelly), Docker
# and podman volumes, and anything under /var/lib — `ucli clean-system` owns the
# container side, and named volumes there hold databases.
#
# paccache comes from pacman-contrib. When it is not installed the fallback is
# `pacman -Sc`, which is blunter (it drops every cached version of uninstalled
# packages) and says so.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

keep=2
dry_run=0
while (($#)); do
  case "$1" in
    --keep) keep="${2:-2}"; shift 2 ;;
    --keep=*) keep="${1#*=}"; shift ;;
    --dry-run|-n) dry_run=1; shift ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ "$keep" =~ ^[0-9]+$ ]] || { echo "--keep takes a number" >&2; exit 2; }

# UCLI_TEST_ROOT is the test seam (setup-boot.sh has the same idea): with it
# set, the root check is skipped so the logic can be exercised on a temp tree.
if (( EUID != 0 )) && [[ -z "${UCLI_TEST_ROOT:-}" ]]; then
  echo "Run as root: sudo ucli fix cache" >&2
  exit 1
fi

cachedir="${UCLI_TEST_ROOT:-}/var/cache/pacman/pkg"

size_of() {
  local dir="$1"
  [[ -d "$dir" ]] || { printf '0\n'; return 0; }
  du -sm "$dir" 2>/dev/null | awk '{print $1}'
}

before_pkg="$(size_of "$cachedir")"
before_journal="$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[MG]' | head -1 || echo '?')"

ui_rule "package cache (${before_pkg} MB)"
if (( dry_run )); then
  if command -v paccache >/dev/null 2>&1; then
    printf '+ paccache -rk%s\n' "$keep"
    printf '+ paccache -ruk0\n'
  else
    printf '+ pacman -Sc --noconfirm   (paccache not installed)\n'
  fi
else
  if command -v paccache >/dev/null 2>&1; then
    printf '  keeping the %s newest version(s) of installed packages\n' "$keep"
    paccache -rk"$keep"
    printf '  dropping every cached version of uninstalled packages\n'
    paccache -ruk0
  else
    printf '  paccache not found (pacman-contrib); using pacman -Sc\n'
    pacman -Sc --noconfirm
  fi
fi

ui_rule "journal (${before_journal})"
if (( dry_run )); then
  printf '+ journalctl --vacuum-size=200M\n'
else
  journalctl --vacuum-size=200M
fi

if (( ! dry_run )); then
  after_pkg="$(size_of "$cachedir")"
  ui_rule "done"
  printf '  package cache: %s MB → %s MB\n' "$before_pkg" "$after_pkg"
  printf '  journal:       %s → %s\n' "$before_journal" \
    "$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[MG]' | head -1 || echo '?')"
fi
