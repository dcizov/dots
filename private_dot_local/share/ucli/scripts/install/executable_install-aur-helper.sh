#!/usr/bin/env bash
set -euo pipefail

# Distro-aware AUR helper selection and installation.
#
#   CachyOS:   shelly is preinstalled; use it (no install needed).
#   Arch/other: ask the user — paru or shelly — then install the chosen one.
#
# The chosen helper name is printed to stdout and stored in
# /etc/ucli/aur-helper so subsequent runs (e.g. setup-desktop.sh as root)
# reuse the same selection without re-prompting.

usage() {
  cat <<'USAGE'
usage: install-aur-helper.sh [--yes] [--print-only]

Options:
  --yes        non-interactive: install default (shelly on CachyOS, paru on Arch)
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

STATE_FILE="/etc/ucli/aur-helper"

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

install_paru() {
  run_as_real_user "$script_dir/install-paru.sh" "$@"
}

install_shelly() {
  run_as_real_user "$script_dir/install-shelly.sh" "$@"
}

main() {
  local distro; distro="$(detect_distro_raw | tr '[:upper:]' '[:lower:]')"
  local stored; stored="$(get_stored_helper)"

  # --print-only: just report the configured helper, don't install
  if (( print_only )); then
    if [[ -n "$stored" ]] && command -v "$stored" >/dev/null 2>&1; then
      printf '%s\n' "$stored"
      return 0
    fi
    # Fall back to distro default without installing
    case "$distro" in
      cachyos) printf 'shelly\n' ;;
      *) printf 'paru\n' ;;
    esac
    return 0
  fi

  # If a helper is already stored and available, reuse it.
  if [[ -n "$stored" ]] && command -v "$stored" >/dev/null 2>&1; then
    printf '%s\n' "$stored"
    return 0
  fi

  case "$distro" in
    cachyos)
      # Shelly is preinstalled on CachyOS; use it.
      if command -v shelly >/dev/null 2>&1; then
        store_helper shelly
        printf 'shelly\n'
      else
        echo "CachyOS detected but shelly not found; installing shelly..." >&2
        install_shelly "${yes_flag:+--yes}"
        store_helper shelly
        printf 'shelly\n'
      fi
      ;;
    arch|archlinux|*)
      # Ask the user which AUR helper to use.
      if [[ -z "$stored" ]]; then
        if (( yes_flag )); then
          # Non-interactive: default to paru (mature, widely used)
          echo "Non-interactive mode: installing paru..." >&2
          install_paru "${yes_flag:+--yes}"
          store_helper paru
          printf 'paru\n'
        else
          echo "No AUR helper configured." >&2
          echo "1) paru  — mature AUR helper (default)" >&2
          echo "2) shelly — modern AUR helper (preinstalled on CachyOS)" >&2
          read -rp "Choose AUR helper (1/2): " choice
          case "$choice" in
            1|paru|"") install_paru "${yes_flag:+--yes}"; store_helper paru; printf 'paru\n' ;;
            2|shelly) install_shelly "${yes_flag:+--yes}"; store_helper shelly; printf 'shelly\n' ;;
            *) echo "Invalid choice" >&2; exit 2 ;;
          esac
        fi
      else
        # Stored helper exists but isn't available; try to install it.
        if command -v "$stored" >/dev/null 2>&1; then
          printf '%s\n' "$stored"
        else
          echo "Stored helper '$stored' not found; please re-run to select." >&2
          exit 1
        fi
      fi
      ;;
  esac
}

main "$@"
