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

# Install desktop packages applying the replacement matrix from packages.bash.
# Skips packages in DESKTOP_SKIP_<DE> and replaces packages in DESKTOP_REPLACE_<DE>.
install_desktop_with_replacements() {
  local de="$1"
  local skip_var="DESKTOP_SKIP_${de^^}"
  local replace_var="DESKTOP_REPLACE_${de^^}"
  local -a skip_pkgs=() replace_pkgs=() replace_flatpaks=()

  # Collect packages to skip
  if [[ -n "${!skip_var:-}" ]]; then
    # shellcheck disable=SC2086
    read -ra skip_pkgs <<< "${!skip_var}"
  fi

  # Collect replacements: "original=replacement"
  if [[ -n "${!replace_var:-}" ]]; then
    # shellcheck disable=SC2086
    for pair in ${!replace_var}; do
      local orig="${pair%%=*}"
      local repl="${pair#*=}"
      replace_pkgs+=("$orig")
      # Check if replacement is a flatpak (contains a dot)
      if [[ "$repl" == *.* ]]; then
        replace_flatpaks+=("$repl")
      else
        replace_pkgs+=("$repl")
      fi
    done
  fi

  # Build the final package list: full DE set minus skipped, plus replacements
  local -a all_pkgs=()
  case "$de" in
    gnome)
      all_pkgs=(gnome-shell gdm nautilus gnome-control-center gnome-session gnome-keyring
                gnome-tweaks gnome-boxes gdm-settings
                nautilus-admin-gtk4 nautilus-my-computer nautilus-open-any-terminal)
      ;;
    hyprland)
      all_pkgs=(hyprland uwsm xdg-desktop-portal-hyprland sddm
                kitty dolphin wofi grim slurp dunst)
      ;;
    kde)
      all_pkgs=(plasma plasma-wayland-session sddm konsole dolphin kate)
      ;;
  esac

  local -a final_pkgs=()
  for pkg in "${all_pkgs[@]}"; do
    local skip=0
    for s in "${skip_pkgs[@]}"; do
      if [[ "$pkg" == "$s" ]]; then skip=1; break; fi
    done
    (( skip )) && continue
    final_pkgs+=("$pkg")
  done

  # Add replacements (non-flatpak)
  for pkg in "${replace_pkgs[@]}"; do
    # Avoid duplicates
    local exists=0
    for e in "${final_pkgs[@]}"; do
      if [[ "$e" == "$pkg" ]]; then exists=1; break; fi
    done
    (( exists )) || final_pkgs+=("$pkg")
  done

  if (( ${#final_pkgs[@]} > 0 )); then
    # shellcheck disable=SC2086
    sudo pacman -S --needed --noconfirm "${final_pkgs[@]}"
  fi

  # Install replacement flatpaks
  if (( ${#replace_flatpaks[@]} > 0 )); then
    if ! command -v flatpak >/dev/null 2>&1; then
      sudo pacman -S --needed --noconfirm flatpak
    fi
    flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    # shellcheck disable=SC2086
    flatpak install --user -y flathub "${replace_flatpaks[@]}"
  fi
}

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
  # Install full desktop package set via the package resolver,
  # applying the replacement matrix (skip + replace).
  install_desktop_with_replacements "$desktop"
fi

# Apply software replacement matrix: skip unwanted packages, install replacements.
# ArchWiki: users should install only what they need from DE groups
# https://wiki.archlinux.org/title/GNOME
apply_replacements() {
  local de="$1"
  local skip_var="DESKTOP_SKIP_${de^^}"
  local replace_var="DESKTOP_REPLACE_${de^^}"
  local -a skip_pkgs=() replace_orig=() replace_with=() replace_flatpaks=()

  if [[ -n "${!skip_var:-}" ]]; then
    # shellcheck disable=SC2086
    read -ra skip_pkgs <<< "${!skip_var}"
  fi
  if [[ -n "${!replace_var:-}" ]]; then
    # shellcheck disable=SC2086
    for pair in ${!replace_var}; do
      local orig="${pair%%=*}"
      local repl="${pair#*=}"
      replace_orig+=("$orig")
      if [[ "$repl" == *.* ]]; then
        replace_flatpaks+=("$repl")
      else
        replace_with+=("$repl")
      fi
    done
  fi

  # Remove skipped packages
  for pkg in "${skip_pkgs[@]}"; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
      echo "removing skipped package: $pkg"
      sudo pacman -Rs --noconfirm "$pkg" 2>/dev/null || true
    fi
  done

  # Replace original packages with alternatives
  for i in "${!replace_orig[@]}"; do
    local orig="${replace_orig[$i]}"
    if pacman -Q "$orig" >/dev/null 2>&1; then
      echo "replacing $orig with ${replace_with[$i]:-<flatpak>}"
      sudo pacman -Rs --noconfirm "$orig" 2>/dev/null || true
    fi
    if [[ ${#replace_with[@]} -gt $i ]] && [[ -n "${replace_with[$i]:-}" ]]; then
      if ! pacman -Q "${replace_with[$i]}" >/dev/null 2>&1; then
        echo "installing replacement: ${replace_with[$i]}"
        sudo pacman -S --needed --noconfirm "${replace_with[$i]}" 2>/dev/null || true
      fi
    fi
  done

  # Install replacement flatpaks
  if (( ${#replace_flatpaks[@]} > 0 )); then
    if ! command -v flatpak >/dev/null 2>&1; then
      sudo pacman -S --needed --noconfirm flatpak
    fi
    flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    # shellcheck disable=SC2086
    flatpak install --user -y flathub "${replace_flatpaks[@]}" 2>/dev/null || true
  fi
}

apply_replacements "$desktop"

# GNOME extensions are handled by the extension-set script.
if [[ "$desktop" == "gnome" ]]; then
  "$script_dir/install-gnome-extension-set.sh" system || true
fi

# Create a snapshot capturing the DE-installed state.
"$script_dir/../system/snapshot-fresh-install.sh" "$desktop Setup"

echo "Desktop $desktop installed and snapshot created."
echo "Next: run 'ucli setup-snapshots' (if not already done), then 'ucli devmode' and 'ucli apps'."
echo "To backup GNOME settings: ucli backup-gnome-settings"
