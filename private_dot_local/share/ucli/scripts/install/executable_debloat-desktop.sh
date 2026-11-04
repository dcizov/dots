#!/usr/bin/env bash
# Review installed desktop packages and remove bloat one by one.
#
# Usage: sudo debloat-desktop.sh [gnome|hyprland|kde]
#
# Philosophy: install the full DE group first (e.g. `pacman -S gnome`),
# then debloat individual packages you don't need. See:
#   https://www.reddit.com/r/gnome/comments/typwrj/arch_users_please_install_the_entire_gnome_before/
#
# Shows every installed package from the DE group (plus override packages)
# and lets you pick which to remove with pacman -Rs.
#
# A Snapper snapshot is taken before anything is removed (skip with
# --no-snapshot, or when snapper is not configured): removing packages is the
# one destructive thing in this repo, and the restore point is free.
#
# The multi-select is the shared one from lib/ui.sh (gum, numbered prompt
# without it), so this screen looks like `ucli devmode` and `ucli setup-desktop`.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/../lib/ui.sh"

if (( EUID != 0 )); then
  echo "Run as root: sudo $0 <gnome|hyprland|kde>" >&2
  exit 1
fi

desktop=""
take_snapshot=1
for arg in "$@"; do
  case "$arg" in
    --no-snapshot) take_snapshot=0 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    -* ) echo "unknown option: $arg" >&2; exit 2 ;;
    *) desktop="$arg" ;;
  esac
done

# Auto-detect desktop: CLI arg → chezmoi profile → environment → installed pkgs
if [[ -z "$desktop" ]]; then
  # chezmoi profile value (set during initial setup)
  if command -v chezmoi >/dev/null 2>&1; then
    desktop="$(chezmoi data 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("desktop","none"))' 2>/dev/null || echo none)"
  fi
fi
if [[ -z "$desktop" || "$desktop" == "none" || "$desktop" == "auto" ]]; then
  # Environment / detected desktop session
  desktop="$(detect_desktop 2>/dev/null || echo none)"
fi
if [[ -z "$desktop" || "$desktop" == "none" ]]; then
  # Installed desktop packages as last resort
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
  *) echo "Invalid desktop: $desktop" >&2; exit 2 ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# Restore point before touching anything. Non-fatal: on a machine without
# snapper there is simply nothing to snapshot, and refusing to debloat over that
# would be silly — but say so loudly, because the removal is not reversible.
# The snapshot script itself decides whether a restore point is possible (snapper
# installed? /etc/snapper/configs/root? btrfs?), so this only forwards the flag.
snapshot_script="$script_dir/../system/snapshot-fresh-install.sh"
if (( take_snapshot )) && [[ -x "$snapshot_script" ]]; then
  echo "Creating a snapshot before debloating ..."
  "$snapshot_script" "before debloat ($desktop)" \
    || echo "warning: snapshot failed; continuing anyway (press Ctrl-C now to abort)" >&2
fi

# shellcheck source=/dev/null
source "$real_home/.config/ucli/packages.bash"

# --- Required packages that should NEVER be offered for removal ---
# These are the core pieces GNOME (or the DE) needs to function.
declare -A REQUIRED=(
  [gnome-shell]=1 [gdm]=1 [nautilus]=1 [gnome-control-center]=1
  [gnome-session]=1 [gnome-keyring]=1 [xdg-desktop-portal-gnome]=1
)

# --- Build candidate package list -----------------------------------------

candidates=()

case "$desktop" in
  gnome)
    # All packages installed from the gnome group (59 packages on Arch).
    # pacman -Qg gnome outputs lines like "gnome baobab" — take the 2nd field.
    if pacman -Qg gnome >/dev/null 2>&1; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        pkg="${line#* }"
        candidates+=("$pkg")
      done < <(pacman -Qg gnome 2>/dev/null)
    fi
    # Add override packages (gnome-boxes, gdm-settings, nautilus-*, etc.) and the
    # extension machinery (extension-manager + the repo-packaged extensions): all
    # of it is optional, and `ucli setup-extensions` puts the extension side back.
    for pkg in "${GNOME_APP_OVERRIDES[@]:-}" "${GNOME_SYSTEM_EXTENSION_PACKAGES[@]:-}"; do
      if pacman -Q "$pkg" >/dev/null 2>&1; then
        candidates+=("$pkg")
      fi
    done
    ;;
  hyprland)
    for pkg in "${DESKTOP_HYPRLAND_BASE[@]:-}" "${DESKTOP_HYPRLAND_ADDITIONS[@]:-}"; do
      if pacman -Q "$pkg" >/dev/null 2>&1; then
        candidates+=("$pkg")
      fi
    done
    ;;
  kde|plasma)
    for pkg in "${DESKTOP_KDE_BASE[@]:-}" "${DESKTOP_KDE_ADDITIONS[@]:-}"; do
      if pacman -Q "$pkg" >/dev/null 2>&1; then
        candidates+=("$pkg")
      fi
    done
    ;;
esac

# Remove required packages and duplicates, preserve order.
declare -A seen=()
final_candidates=()
for pkg in "${candidates[@]}"; do
  [[ -n "${REQUIRED[$pkg]:-}" ]] && continue
  [[ -n "${seen[$pkg]:-}" ]] && continue
  seen[$pkg]=1
  final_candidates+=("$pkg")
done

if (( ${#final_candidates[@]} == 0 )); then
  echo "No debloatable $desktop packages found installed."
  exit 0
fi

echo "Installed $desktop packages eligible for removal:"
echo "(required packages like gnome-shell, gdm, nautilus are excluded)"
echo

# --- Multi-select ----------------------------------------------------------

chosen=()
items=()
for pkg in "${final_candidates[@]}"; do items+=("$pkg"); done
if picked="$(ui_choose_multi "$desktop debloat — packages to remove" --height 18 "${items[@]}")"; then
  mapfile -t chosen <<<"$picked"
else
  echo "Cancelled."
  exit 0
fi

if (( ${#chosen[@]} == 0 )); then
  echo "No packages selected."
  exit 0
fi

echo
echo "Removing: ${chosen[*]}"
echo
pacman -Rs --noconfirm "${chosen[@]}"

echo
echo "Debloat complete for $desktop."