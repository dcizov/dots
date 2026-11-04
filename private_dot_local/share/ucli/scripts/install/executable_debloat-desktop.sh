#!/usr/bin/env bash
# Review installed desktop packages and remove bloat.
#
# Usage: sudo debloat-desktop.sh [gnome|hyprland|kde]
#
# Shows package groups for the selected DE and lets you deselect packages
# you don't want. Removes them with pacman -Rs (recursive, with deps).
#
# Intended for after setup-desktop.sh when you realize some of the
# installed packages are unnecessary for your setup.
#
# Interactive selector order: gum -> fzf -> plain select.
set -euo pipefail

if (( EUID != 0 )); then
  echo "Run as root: sudo $0 <gnome|hyprland|kde>" >&2
  exit 1
fi

desktop="${1:-}"
if [[ -z "$desktop" ]]; then
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

# Package groups per DE, each with a description and whether it's installed.
declare -A groups=()
declare -A pkgs=()

case "$desktop" in
  gnome)
    groups[core]="GNOME shell + core apps (required)"
    pkgs[core]="gnome-shell gdm nautilus gnome-control-center gnome-session gnome-keyring"
    groups[tweaks]="Appearance customization"
    pkgs[tweaks]="gnome-tweaks"
    groups[vms]="Virtual machine manager"
    pkgs[vms]="gnome-boxes"
    groups[gdm-config]="GDM theme and configuration"
    pkgs[gdm-config]="gdm-settings"
    groups[nautilus-ext]="Nautilus file manager extensions"
    pkgs[nautilus-ext]="nautilus-admin-gtk4 nautilus-my-computer nautilus-open-any-terminal"
    ;;
  hyprland)
    groups[core]="Hyprland compositor + session essentials (required)"
    pkgs[core]="hyprland uwsm xdg-desktop-portal-hyprland sddm"
    groups[terminal]="Terminal emulator (kitty — replace with ghostty if you prefer)"
    pkgs[terminal]="kitty"
    groups[file-manager]="File manager (dolphin)"
    pkgs[file-manager]="dolphin"
    groups[launcher]="App launcher (wofi)"
    pkgs[launcher]="wofi"
    groups[screenshot]="Screenshot tools (grim, slurp)"
    pkgs[screenshot]="grim slurp"
    groups[notifications]="Notification daemon (dunst)"
    pkgs[notifications]="dunst"
    ;;
  kde)
    groups[core]="KDE Plasma desktop (required)"
    pkgs[core]="plasma plasma-wayland-session sddm"
    groups[apps]="Core KDE apps (kwi, dolphin, kate)"
    pkgs[apps]="kwi dolphin kate"
    ;;
esac

# Check which groups have any installed packages.
installed_groups=()
for name in "${!groups[@]}"; do
  pkg_list="${pkgs[$name]}"
  installed=0
  for p in $pkg_list; do
    if pacman -Q "$p" >/dev/null 2>&1; then
      installed=1
      break
    fi
  done
  if (( installed )); then
    installed_groups+=("$name")
  fi
done

if (( ${#installed_groups[@]} == 0 )); then
  echo "No $desktop packages found installed. Nothing to debloat."
  exit 0
fi

echo "Installed $desktop package groups:"
echo

# Build selector items: "group — description"
items=()
item_to_group=()
for name in "${installed_groups[@]}"; do
  items+=("$name — ${groups[$name]}")
  item_to_group+=("$name")
done

# Choose selector backend.
choose_one() {
  local prompt="$1"; shift
  if command -v gum >/dev/null 2>&1; then
    printf '%s\n' "$@" | gum choose --header "$desktop debloat"
  elif command -v fzf >/dev/null 2>&1; then
    printf '%s\n' "$@" | fzf --prompt "$prompt " --header "$desktop debloat"
  else
    local i=0
    for item in "$@"; do
      printf '  %d) %s\n' "$((++i))" "$item"
    done
    read -rp "Select a group number: " sel
    printf '%s\n' "${items[$((sel - 1))]}"
  fi
}

while true; do
  echo
  chosen="$(choose_one 'Select a group to review (or press Enter/Ctrl-C to finish):' "${items[@]:-}")" || break
  [ -n "$chosen" ] || break

  # Extract group name from "name — description"
  group_name="${chosen%% — *}"

  echo
  echo "Group: $group_name — ${groups[$group_name]}"
  echo "Packages: ${pkgs[$group_name]}"
  echo

  read -rp "Remove these packages? [y/N] " ans
  if [[ "$ans" == y || "$ans" == Y || "$ans" == yes ]]; then
    # shellcheck disable=SC2086
    pacman -Rs --noconfirm ${pkgs[$group_name]} 2>/dev/null || true
    echo "Removed $group_name packages."
    # Remove from items so we don't offer it again
    new_items=(); new_groups=()
    for i in "${!items[@]}"; do
      if [[ "${items[$i]}" != "$chosen" ]]; then
        new_items+=("${items[$i]}")
        new_groups+=("${item_to_group[$i]}")
      fi
    done
    items=("${new_items[@]}")
    item_to_group=("${new_groups[@]}")
    if (( ${#items[@]} == 0 )); then
      echo "No more groups to review."
      break
    fi
  fi
done

echo
echo "Debloat complete for $desktop."
