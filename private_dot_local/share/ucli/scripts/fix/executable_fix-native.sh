#!/usr/bin/env bash
# Reinstall every repository package in place: the blunt repair for a machine whose
# files have drifted (a half-finished upgrade, a /usr that something wrote into, a
# library that vanished).
#
#   sudo ucli fix native --list        how many packages, and the first 20 names
#   sudo ucli fix native               reinstall them, after a typed confirmation
#   sudo ucli fix native --yes         no confirmation (scripts)
#   sudo ucli fix native --dry-run     the exact command, change nothing
#
# Scope: `pacman -Qnq` (native, i.e. repo packages) intersected with what the sync
# databases still carry, so a package that was dropped from the repos is skipped
# instead of failing the whole transaction. AUR/foreign packages are never touched
# — they would need a rebuild, and that is `paru -Sua`, not this.
#
# Targets are fed on stdin (`pacman -S -`), because a few thousand package names do
# not fit in one argv on a busy machine.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

yes_flag=0
list_only=0
dry_run=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) yes_flag=1 ;;
    --list) list_only=1 ;;
    --dry-run|-n) dry_run=1 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# UCLI_TEST_ROOT is the test seam (setup-boot.sh has the same idea): with it
# set, the root check is skipped so the logic can be exercised on a temp tree.
if (( EUID != 0 )) && [[ -z "${UCLI_TEST_ROOT:-}" ]]; then
  echo "Run as root: sudo ucli fix native" >&2
  exit 1
fi

ui_rule "repository packages"
mapfile -t native < <(pacman -Qnq 2>/dev/null || true)
if (( ${#native[@]} == 0 )); then
  echo "  no native packages found (is pacman's database readable?)" >&2
  exit 1
fi

reinstallable=()
skipped=()
for pkg in "${native[@]}"; do
  if pacman -Si "$pkg" >/dev/null 2>&1; then
    reinstallable+=("$pkg")
  else
    skipped+=("$pkg")
  fi
done

printf '  native:      %s\n' "${#native[@]}"
printf '  in repos:    %s\n' "${#reinstallable[@]}"
if (( ${#skipped[@]} )); then
  printf '  skipped:     %s (dropped from the repos)\n' "${#skipped[@]}"
  printf '    %s\n' "${skipped[@]:0:10}"
fi

if (( list_only )); then
  printf '  first 20:    %s\n' "${reinstallable[*]:0:20}"
  exit 0
fi
if (( ${#reinstallable[@]} == 0 )); then
  echo "nothing to reinstall" >&2
  exit 1
fi

cmd=(pacman -S --needed --noconfirm -)
if (( dry_run )); then
  printf '+ printf "%%s\\n" <%s package names> | sudo %s\n' "${#reinstallable[@]}" "${cmd[*]}"
  exit 0
fi

if (( ! yes_flag )) && [[ -t 0 ]]; then
  printf '\nThis re-downloads and reinstalls %s packages. It is slow but safe:\n' "${#reinstallable[@]}"
  printf 'config files with local changes are kept (pacman .pacnew rules apply).\n'
  printf 'Type "reinstall" to continue: '
  read -r answer || exit 1
  [[ "$answer" == "reinstall" ]] || { echo "aborted."; exit 1; }
fi

printf '%s\n' "${reinstallable[@]}" | "${cmd[@]}"
ui_ok "reinstalled ${#reinstallable[@]} repository package(s)"
printf '  reboot if the reinstall replaced a kernel or driver.\n'
