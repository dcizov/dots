#!/usr/bin/env bash
# Set up a desktop environment and snapshot afterwards.
#
# Usage: sudo setup-desktop.sh <gnome|hyprland|kde>
#
# Installs the desktop package set, creates a Snapper snapshot named
# "<DE> Setup", and leaves the system ready for ucli setup (devmode/apps).
#
# Intended for Arch minimal (archinstall) post-console-first-boot flow:
#   1. sudo install.sh            # bootstrap chezmoi/ucli
#   2. chezmoi apply              # deploy dotfiles
#   3. sudo setup-desktop.sh gnome  # install DE + snapshot
#   4. ucli setup-snapshots       # system-level snapper/limine (if not done)
#   5. ucli devmode               # dev packages
#   6. ucli apps                  # personal apps
set -euo pipefail

choose=0
if [[ "${1:-}" == "--choose" ]]; then
  choose=1
  shift
fi

if (( EUID != 0 )); then
  echo "Run as root: sudo $0 [--choose] <gnome|hyprland|kde>" >&2
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

# shellcheck source=/dev/null
source "$script_dir/../../packages.bash"

if (( choose )); then
  # Interactive: let user pick which package groups to install.
  declare -A groups=()
  declare -A pkgs=()

  case "$desktop" in
    gnome)
      groups[core]="GNOME shell + core apps (required)"
      pkgs[core]="gnome-shell gdm nautilus gnome-control-center gnome-session gnome-keyring"
      groups[tweaks]="Appearance customization (gnome-tweaks)"
      pkgs[tweaks]="gnome-tweaks"
      groups[vms]="Virtual machine manager (gnome-boxes — remove if unused)"
      pkgs[vms]="gnome-boxes"
      groups[gdm-config]="GDM theme/config (gdm-settings — remove if defaults OK)"
      pkgs[gdm-config]="gdm-settings"
      groups[nautilus-ext]="Nautilus extensions (admin, my-computer, open-any-terminal)"
      pkgs[nautilus-ext]="nautilus-admin-gtk4 nautilus-my-computer nautilus-open-any-terminal"
      ;;
    hyprland)
      groups[core]="Hyprland compositor + session essentials (required)"
      pkgs[core]="hyprland uwsm xdg-desktop-portal-hyprland sddm"
      groups[terminal]="Terminal (kitty — replace with ghostty if preferred)"
      pkgs[terminal]="kitty"
      groups[file-manager]="File manager (dolphin — remove if unused)"
      pkgs[file-manager]="dolphin"
      groups[launcher]="App launcher (wofi — remove if unused)"
      pkgs[launcher]="wofi"
      groups[screenshot]="Screenshot tools (grim slurp — remove if unused)"
      pkgs[screenshot]="grim slurp"
      groups[notifications]="Notification daemon (dunst)"
      pkgs[notifications]="dunst"
      ;;
    kde)
      groups[core]="KDE Plasma desktop (required)"
      pkgs[core]="plasma plasma-wayland-session sddm"
      groups[apps]="Core KDE apps (konsole dolphin kate)"
      pkgs[apps]="konsole dolphin kate"
      ;;
  esac

  echo "Select $desktop package groups to install:"
  echo
  items=()
  item_to_group=()
  for name in "${!groups[@]}"; do
    items+=("$name — ${groups[$name]}")
    item_to_group+=("$name")
  done

  # Sort so core is first
  IFS=$'\n' sorted=($(sort <<<"${items[*]}")); unset IFS

  choose_one() {
    local prompt="$1"; shift
    if command -v gum >/dev/null 2>&1; then
      printf '%s\n' "$@" | gum choose --prompt "$prompt " --header "$desktop packages"
    elif command -v fzf >/dev/null 2>&1; then
      printf '%s\n' "$@" | fzf --prompt "$prompt " --header "$desktop packages" --multi
    else
      local i=0
      for item in "$@"; do
        printf '  %d) %s\n' "$((++i))" "$item"
      done
      read -rp "Select group numbers (space-separated): " sels
      for s in $sels; do
        printf '%s\n' "${sorted[$((s - 1))]}"
      done
    fi
  }

  chosen=()
  while IFS= read -r line; do
    [ -n "$line" ] && chosen+=("$line")
  done < <(choose_one 'Select groups to install (space/Enter to confirm):' "${sorted[@]:-}")

  if (( ${#chosen[@]} == 0 )); then
    echo "No groups selected. Aborting."
    exit 1
  fi

  install_pkgs=()
  for c in "${chosen[@]}"; do
    gname="${c%% — *}"
    # shellcheck disable=SC2086
    install_pkgs+=(${pkgs[$gname]})
  done

  # shellcheck disable=SC2086
  sudo pacman -S --needed --noconfirm "${install_pkgs[@]}"
else
  # Install full desktop package set via the package resolver.
  "$script_dir/install-packages.sh" desktop --desktop="$desktop"
fi

# GNOME extensions are handled by the extension-set script.
if [[ "$desktop" == "gnome" ]]; then
  "$script_dir/install-gnome-extension-set.sh" system || true
fi

# Create a snapshot capturing the DE-installed state.
"$script_dir/../system/snapshot-fresh-install.sh" "$desktop Setup"

echo "Desktop $desktop installed and snapshot created."
echo "Next: run 'ucli setup-snapshots' (if not already done), then 'ucli devmode' and 'ucli apps'."
