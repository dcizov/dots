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
# Interactive selector order: gum -> fzf -> plain select.
set -euo pipefail

if (( EUID != 0 )); then
  echo "Run as root: sudo $0 <gnome|hyprland|kde>" >&2
  exit 1
fi

desktop="${1:-}"

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
  read -rp "Desktop [gnome/hyprland/kde]: " desktop
fi
case "$desktop" in
  gnome|hyprland|kde) ;;
  *) echo "Invalid desktop: $desktop" >&2; exit 2 ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

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
    # Add override packages (gnome-boxes, gdm-settings, nautilus-*, etc.)
    for pkg in "${GNOME_APP_OVERRIDES[@]:-}"; do
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
if command -v gum >/dev/null 2>&1; then
  # gum choose defaults to multi-select (space to toggle, enter to confirm)
  tmpfile="$(mktemp)"
  # gum choose --no-limit enables multi-select (space to toggle)
  if ! printf '%s\n' "${final_candidates[@]}" | gum choose --no-limit --header "$desktop debloat — select packages to remove" > "$tmpfile"; then
    echo "Cancelled."
    rm -f "$tmpfile"
    exit 0
  fi
  mapfile -t chosen < "$tmpfile"
  rm -f "$tmpfile"
elif command -v fzf >/dev/null 2>&1; then
  tmpfile="$(mktemp)"
  if ! printf '%s\n' "${final_candidates[@]}" | fzf --multi --header "Select $desktop packages to remove" > "$tmpfile"; then
    echo "Cancelled."
    rm -f "$tmpfile"
    exit 0
  fi
  mapfile -t chosen < "$tmpfile"
  rm -f "$tmpfile"
else
  i=0
  for pkg in "${final_candidates[@]}"; do
    printf '  %d) %s\n' "$((++i))" "$pkg"
  done
  echo
  read -rp "Select package numbers (space-separated): " sels
  for s in $sels; do
    if (( s >= 1 && s <= ${#final_candidates[@]} )); then
      chosen+=("${final_candidates[$((s - 1))]}")
    fi
  done
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