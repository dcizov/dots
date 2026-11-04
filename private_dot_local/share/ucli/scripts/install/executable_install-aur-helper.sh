#!/usr/bin/env bash
set -euo pipefail

# Distro-aware AUR helper selection and installation.
#
# Priority order:
#   1. shelly (if already installed) — preferred for day-to-day use
#   2. paru   (if already installed) — fallback
#   3. install paru (default on Arch) — first-run bootstrap
#
# The chosen helper name is printed to stdout and stored in
# $HOME/.local/share/ucli/aur-helper so subsequent runs reuse the same
# selection without re-prompting. Userspace only — no /etc writes.
#
# STDOUT CONTRACT: exactly one line, the helper name. Every installer's own
# output goes to stderr, and the answer is verified with `command -v` after the
# install rather than taken on trust. Callers do `helper="$(install-aur-helper.sh)"`
# and then compare it to "paru"/"shelly"; install-paru.sh printing "cloning paru
# AUR repository ..." on stdout used to end up inside that variable, which is
# how `ucli setup-snapshots` died with "paru not available after install
# attempt" right after pacman had reported paru installed.

usage() {
  cat <<'USAGE'
usage: install-aur-helper.sh [--yes] [--print-only]

Options:
  --yes        non-interactive: install default (paru on Arch, shelly on CachyOS)
  --print-only print the configured helper name without installing anything
USAGE
}

yes_flag=0
print_only=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) yes_flag=1 ;;
    --print-only) print_only=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

STATE_FILE="${HOME:-$(getent passwd "${USER:-root}" | cut -d: -f6)}/.local/share/ucli/aur-helper"

get_stored_helper() {
  [ -r "$STATE_FILE" ] && cat "$STATE_FILE" || printf ''
}

store_helper() {
  local helper="$1"
  mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
  printf '%s\n' "$helper" > "$STATE_FILE" 2>/dev/null || true
}

detect_distro_raw() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s\n' "${ID:-unknown}"
  else
    printf 'unknown\n'
  fi
}

# When run as root (e.g. from setup-desktop.sh), drop to the invoking user
# for AUR helper installation since makepkg refuses to run as root.
run_as_real_user() {
  if [[ "$EUID" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
    runuser -u "$SUDO_USER" -- "$@"
  else
    "$@"
  fi
}

# The helper that is really on PATH now — never the string the installer
# claimed. Stores it and prints the single line callers rely on.
pick_installed() {
  if command -v shelly >/dev/null 2>&1; then
    store_helper shelly
    printf 'shelly\n'
    return 0
  fi
  if command -v paru >/dev/null 2>&1; then
    store_helper paru
    printf 'paru\n'
    return 0
  fi
  return 1
}

install_paru() {
  run_as_real_user "$script_dir/install-paru.sh" "$@"
}

install_shelly() {
  run_as_real_user "$script_dir/install-shelly.sh" "$@"
}

main() {
  local distro; distro="$(detect_distro_raw | tr '[:upper:]' '[:lower:]')"
  local stored; stored="$(get_stored_helper)"

  # --print-only: just report the preferred helper, don't install
  if (( print_only )); then
    if command -v shelly >/dev/null 2>&1; then
      printf 'shelly\n'
    elif command -v paru >/dev/null 2>&1; then
      printf 'paru\n'
    elif [[ -n "$stored" ]]; then
      printf '%s\n' "$stored"
    else
      case "$distro" in
        cachyos) printf 'shelly\n' ;;
        *) printf 'paru\n' ;;
      esac
    fi
    return 0
  fi

  # Already there: shelly wins over paru, both win over installing anything.
  pick_installed && return 0

  # Nothing installed. CachyOS defaults to shelly, everything else to paru; a
  # human gets asked unless --yes.
  local want=shelly
  [[ "$distro" == cachyos ]] || want=paru

  if (( ! yes_flag )); then
    echo "No AUR helper installed." >&2
    want="$(ui_choose "Which AUR helper?" \
      'paru|mature AUR helper (the default)' \
      'shelly|modern AUR helper, preinstalled on CachyOS')" || exit 2
  fi

  local -a yes_args=()
  (( yes_flag )) && yes_args=(--yes)

  case "$want" in
    paru)   echo "Installing paru..." >&2 ; install_paru "${yes_args[@]+"${yes_args[@]}"}" >&2 ;;
    shelly) echo "Installing shelly..." >&2 ; install_shelly "${yes_args[@]+"${yes_args[@]}"}" >&2 ;;
    *) echo "Invalid choice: $want" >&2; exit 2 ;;
  esac

  # Installed is what `command -v` says, not what the installer printed.
  if ! pick_installed; then
    echo "no AUR helper on PATH after installing $want" >&2
    exit 1
  fi
}

main "$@"