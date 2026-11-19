#!/usr/bin/env bash
# Review installed desktop packages and remove bloat one by one.
#
# Usage: sudo debloat-desktop.sh [gnome|hyprland|kde] [--no-snapshot]
#        debloat-desktop.sh [DE] --list            print what is eligible, no root
#        sudo debloat-desktop.sh [DE] --remove a,b  remove those, no menu
#
# Philosophy: install the full DE group first (e.g. `pacman -S gnome`),
# then debloat individual packages you don't need. See:
#   https://www.reddit.com/r/gnome/comments/typwrj/arch_users_please_install_the_entire_gnome_before/
#
# Shows every installed package from the DE group (plus override packages)
# and lets you pick which to remove with pacman -Rs.
#
# This is the "and what else?" pass. The packages this repo removes on its own —
# epiphany, gnome-console, gnome-software, gnome-tour, gnome-user-docs, malcontent,
# yelp on GNOME — are DESKTOP_REMOVE_<DE> in packages.bash and are gone before this
# screen is reachable, so they only show up here on a machine that never ran
# setup-desktop.
#
# A Snapper snapshot is taken right before the removal, once there is something
# to remove (skip with --no-snapshot, or when snapper is not configured):
# removing packages is the one destructive thing in this repo, and the restore
# point is free. Each desktop's core packages are never offered.
#
# The multi-select is the shared one from lib/ui.sh (gum, numbered prompt
# without it), so this screen looks like `ucli devmode` and `ucli setup-desktop`.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$script_dir/../lib/common.sh"
# shellcheck source=../lib/detect.sh
. "$script_dir/../lib/detect.sh"

desktop=""
take_snapshot=1
list_only=0
remove_csv=""
while (($#)); do
  case "$1" in
    --no-snapshot) take_snapshot=0 ;;
    --list) list_only=1 ;;
    --remove) remove_csv="${2:-}"; (($# >= 2)) && shift ;;
    --remove=*) remove_csv="${1#*=}" ;;
    -h|--help) ucli_script_help; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) desktop="$1" ;;
  esac
  shift
done

# Auto-detect desktop: argument → chezmoi data → the running session →
# installed packages → ask.
if [[ -z "$desktop" ]]; then
  desktop="$(ucli_profile_value desktop none)"
fi
if [[ -z "$desktop" || "$desktop" == "none" || "$desktop" == "auto" ]]; then
  desktop="$(detect_desktop 2>/dev/null || echo none)"
fi
if [[ -z "$desktop" || "$desktop" == "none" ]]; then
  if pacman -Q gnome-shell >/dev/null 2>&1; then desktop="gnome"
  elif { pacman -Q plasma-desktop >/dev/null 2>&1 || pacman -Q plasma-meta >/dev/null 2>&1; }; then desktop="kde"
  elif pacman -Q hyprland >/dev/null 2>&1; then desktop="hyprland"
  fi
fi
if [[ -z "$desktop" || "$desktop" == "none" ]]; then
  desktop="$(ui_choose "Which desktop?" \
    'gnome|GNOME Shell' 'hyprland|Hyprland' 'kde|KDE Plasma')" || exit 2
fi
case "$desktop" in
  gnome|hyprland|kde) ;;
  plasma) desktop=kde ;;
  *) echo "Invalid desktop: $desktop" >&2; exit 2 ;;
esac

ucli_load_packages "$(ucli_real_home)"

# --- packages that must never be offered: the desktop itself ---------------
declare -A REQUIRED=()
case "$desktop" in
  gnome)    required=(gnome-shell gdm nautilus gnome-control-center gnome-session gnome-keyring xdg-desktop-portal-gnome) ;;
  kde)      required=(plasma-desktop plasma-workspace plasma-meta kwin sddm systemsettings dolphin xdg-desktop-portal-kde) ;;
  hyprland) required=(hyprland xdg-desktop-portal-hyprland) ;;
esac
for pkg in "${required[@]}"; do REQUIRED[$pkg]=1; done

# --- candidates: what is installed from the desktop's sets -------------------
candidates=()
add_installed() {
  local pkg
  for pkg in "$@"; do
    [[ -n "$pkg" ]] && pacman -Q "$pkg" >/dev/null 2>&1 && candidates+=("$pkg")
  done
  return 0
}
case "$desktop" in
  gnome)
    # The whole gnome group ("gnome baobab" lines), plus the app overrides and
    # the extension machinery — all optional; `ucli setup-extensions` puts the
    # extension side back.
    while IFS= read -r line; do
      [[ -n "$line" ]] && candidates+=("${line#* }")
    done < <(pacman -Qg gnome 2>/dev/null || true)
    add_installed "${GNOME_APP_OVERRIDES[@]:-}" "${GNOME_SYSTEM_EXTENSION_PACKAGES[@]:-}"
    ;;
  hyprland) add_installed "${DESKTOP_HYPRLAND_BASE[@]:-}" "${DESKTOP_HYPRLAND_ADDITIONS[@]:-}" ;;
  kde)      add_installed "${DESKTOP_KDE_BASE[@]:-}" "${DESKTOP_KDE_ADDITIONS[@]:-}" ;;
esac

# Drop the required ones and duplicates, keep the order.
declare -A eligible=()
final_candidates=()
for pkg in "${candidates[@]}"; do
  [[ -n "${REQUIRED[$pkg]:-}" || -n "${eligible[$pkg]:-}" ]] && continue
  eligible[$pkg]=1
  final_candidates+=("$pkg")
done

if (( ${#final_candidates[@]} == 0 )); then
  echo "No debloatable $desktop packages found installed."
  exit 0
fi
if (( list_only )); then
  printf '%s\n' "${final_candidates[@]}"
  exit 0
fi

# --- what to remove: --remove, or the menu ----------------------------------
chosen=()
if [[ -n "$remove_csv" ]]; then
  for pkg in ${remove_csv//,/ }; do
    if [[ -z "${eligible[$pkg]:-}" ]]; then
      echo "not removable here: $pkg (not installed, or part of the $desktop core; see --list)" >&2
      exit 2
    fi
    chosen+=("$pkg")
  done
else
  echo "Installed $desktop packages eligible for removal:"
  echo "(the desktop's own core packages are excluded)"
  echo
  if picked="$(ui_choose_multi "$desktop debloat — packages to remove" --height 18 "${final_candidates[@]}")"; then
    while IFS= read -r pkg; do [[ -n "$pkg" ]] && chosen+=("$pkg"); done <<<"$picked"
  else
    echo "Cancelled."
    exit 0
  fi
fi
if (( ${#chosen[@]} == 0 )); then
  echo "No packages selected."
  exit 0
fi

# UCLI_TEST_ROOT is the test seam the fix scripts use: it skips the root check.
if (( EUID != 0 )) && [[ -z "${UCLI_TEST_ROOT:-}" ]]; then
  echo "Removing packages needs root: ucli debloat-desktop $desktop (the recipe uses sudo)" >&2
  exit 1
fi

# Restore point right before the removal. Non-fatal: the snapshot script decides
# whether one is possible (snapper, its root config, btrfs) — but say so loudly,
# because the removal is not reversible.
snapshot_script="$script_dir/../system/snapshot-fresh-install.sh"
if (( take_snapshot )) && [[ -x "$snapshot_script" ]]; then
  echo "Creating a snapshot before debloating ..."
  "$snapshot_script" "before debloat ($desktop)" \
    || echo "warning: snapshot failed; continuing anyway (press Ctrl-C now to abort)" >&2
fi

echo
echo "Removing: ${chosen[*]}"
echo
pacman -Rs --noconfirm "${chosen[@]}"

echo
echo "Debloat complete for $desktop."
