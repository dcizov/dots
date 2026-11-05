#!/usr/bin/env bash
set -euo pipefail

# Distro-aware AUR helper selection and installation.
#
# Priority order:
#   1. AUR_HELPER from ~/.config/ucli/packages.bash (or the overlay) — if you
#      said which one you want, that is the answer, even if the other is installed
#   2. shelly (if already installed) — preferred for day-to-day use
#   3. paru   (if already installed) — fallback
#   4. install AUR_HELPER, or the distro default (paru on Arch, shelly on CachyOS)
#
# Nothing is written any more. This used to drop the chosen name into
# ~/.local/share/ucli/aur-helper and read it back on the next run; that file was a
# cache of something `command -v` can answer in a millisecond, and a state file for
# a single word is worse than no file. `AUR_HELPER` is the actual preference
# (unset/empty = "pick for me"), and it lives where every other "what this machine
# gets" value lives, so it is the same file you already edit for packages.
# Userspace only — no /etc writes.
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

# The preference lives in the config of the user who will run the helper, which
# is not necessarily the user running this script: from setup-desktop or
# arch-snapper-limine that is root with SUDO_USER set.
config_home() {
  if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    getent passwd "$SUDO_USER" | cut -d: -f6
  else
    printf '%s\n' "${HOME:-$(getent passwd "${USER:-root}" | cut -d: -f6)}"
  fi
}

# AUR_HELPER="paru" in packages.bash, or anything else in the overlay. Both files
# are plain assignments, which is why they can be sourced here.
load_preference() {
  local home cfg
  home="$(config_home)"
  AUR_HELPER="${AUR_HELPER:-}"
  for cfg in "$home/.config/ucli/packages.bash" "$home/.config/ucli/packages.local.bash"; do
    [[ -r "$cfg" ]] || continue
    # shellcheck source=/dev/null
    . "$cfg"
  done
  AUR_HELPER="${AUR_HELPER:-}"
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
# claimed. An explicit AUR_HELPER wins; otherwise shelly, then paru.
pick_installed() {
  local want="${AUR_HELPER:-}"
  if [[ -n "$want" ]]; then
    if command -v "$want" >/dev/null 2>&1; then
      printf '%s\n' "$want"
      return 0
    fi
    return 1
  fi
  if command -v shelly >/dev/null 2>&1; then
    printf 'shelly\n'
    return 0
  fi
  if command -v paru >/dev/null 2>&1; then
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
  load_preference
  local distro; distro="$(detect_distro_raw | tr '[:upper:]' '[:lower:]')"

  # --print-only: just report the helper that would be used, don't install. A
  # configured name this script cannot drive is an error here too — printing it
  # would make the callers (install-packages, setup-desktop, arch-snapper-limine)
  # build a command that is guaranteed to fail.
  if (( print_only )); then
    case "${AUR_HELPER:-}" in
      ""|paru|shelly) ;;
      *) echo "AUR_HELPER=$AUR_HELPER is not a helper this script knows (paru|shelly)" >&2; return 2 ;;
    esac
    if pick_installed; then
      return 0
    fi
    case "${AUR_HELPER:-}" in
      paru|shelly) printf '%s\n' "$AUR_HELPER" ;;
      "") case "$distro" in cachyos) printf 'shelly\n' ;; *) printf 'paru\n' ;; esac ;;
    esac
    return 0
  fi

  # Already there: an explicit preference or shelly beats paru, and both beat
  # installing anything.
  pick_installed && return 0

  # Nothing usable installed. AUR_HELPER wins, then CachyOS' shelly, then paru; a
  # human gets asked unless --yes.
  local want="${AUR_HELPER:-}"
  if [[ -z "$want" ]]; then
    want=shelly
    [[ "$distro" == cachyos ]] || want=paru
  fi
  case "$want" in
    paru|shelly) ;;
    *) echo "AUR_HELPER=$want is not a helper this script knows (paru|shelly)" >&2; exit 2 ;;
  esac

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