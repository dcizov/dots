#!/usr/bin/env bash
# Set up a desktop environment and snapshot afterwards.
#
# Usage: sudo setup-desktop.sh <gnome|hyprland|kde>
#
# Installs the desktop package set, then the firefox + terminal pair that desktop
# is configured for, then the shell tier, then GNOME extensions, then applies the
# dotfiles that need those programs to exist, then snapshots as "<DE> Setup".
#
# Intended for Arch minimal (archinstall) post-console-first-boot flow:
#   1. curl -fsSL https://install.wtfaq.tech | bash   # git, chezmoi, just, ucli
#   2. ucli setup-snapshots        # snapper + limine, snapshot #1 (btrfs)
#   3. ucli setup-system gnome     # base packages, then this script
#   4. ucli devmode / ucli apps    # optional extras
#
# Everything a TTY-only machine needs before step 3 is ucli itself: until the
# desktop exists, .chezmoiignore keeps ~/.zshrc, starship, ~/.config/ghostty and
# ~/.config/firefox out of $HOME, so the fresh-install snapshot stays minimal.
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

# Resolve the AUR helper (distro-aware; cached in /etc/ucli/aur-helper).
# Run as the real user since this may install the helper via makepkg (no root).
aur_helper="$(runuser -u "$real_user" -- "$script_dir/install-aur-helper.sh")"
echo "AUR helper: $aur_helper"

# Enable GDM for GNOME desktop.
if [[ "$desktop" == "gnome" ]]; then
  systemctl enable gdm.service 2>/dev/null || true
fi

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
      # Use DESKTOP_GNOME_BASE which already includes `gnome` (full group)
      # + gnome-tweaks. Skip/replace logic below still applies on top.
      all_pkgs=("${DESKTOP_GNOME_BASE[@]}")
      ;;
    hyprland)
      # No terminal here: install-packages.sh essentials picks it per desktop.
      all_pkgs=(hyprland uwsm xdg-desktop-portal-hyprland sddm
                dolphin wofi grim slurp dunst)
      ;;
    kde)
      all_pkgs=(plasma plasma-wayland-session sddm dolphin kate)
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

  # Install base packages one by one. Handles both individual packages
  # and package groups (e.g. 'gnome' group with 59 packages). AUR-only
  # packages are skipped here — handled by apply_replacements via AUR helper.
  for pkg in "${final_pkgs[@]}"; do
    if pacman -Si "$pkg" >/dev/null 2>&1 || pacman -Sgq "$pkg" >/dev/null 2>&1; then
      sudo pacman -S --needed --noconfirm "$pkg"
    else
      echo "  skipping $pkg: not in repos (handled by AUR helper if it's a replacement)"
    fi
  done

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
      groups[core]="GNOME full desktop + core apps (required)"
      pkgs[core]="${DESKTOP_GNOME_BASE[*]}"
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
      groups[terminal]="Terminal (ghostty, the configured one)"
      pkgs[terminal]="ghostty"
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
      groups[apps]="Core KDE apps (dolphin kate)"
      pkgs[apps]="dolphin kate"
      groups[terminal]="Terminal (kitty, the configured one on Plasma)"
      pkgs[terminal]="kitty"
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
      printf '%s\n' "$@" | gum choose --header "$desktop packages"
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

  for pkg in "${install_pkgs[@]}"; do
    if pacman -Si "$pkg" >/dev/null 2>&1 || pacman -Sgq "$pkg" >/dev/null 2>&1; then
      sudo pacman -S --needed --noconfirm "$pkg"
    else
      echo "  skipping $pkg: not in repos"
    fi
  done
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

  # Replace original packages with alternatives.
  # Non-flatpak replacements: try pacman first (repo packages), then paru (AUR).
  # ArchWiki: AUR packages require an AUR helper like paru
  # https://wiki.archlinux.org/title/Arch_User_Repository
  for i in "${!replace_orig[@]}"; do
    local orig="${replace_orig[$i]}"
    if pacman -Q "$orig" >/dev/null 2>&1; then
      echo "replacing $orig with ${replace_with[$i]:-<flatpak>}"
      sudo pacman -Rs --noconfirm "$orig" 2>/dev/null || true
    fi
    if [[ ${#replace_with[@]} -gt $i ]] && [[ -n "${replace_with[$i]:-}" ]]; then
      if ! pacman -Q "${replace_with[$i]}" >/dev/null 2>&1; then
        echo "installing replacement: ${replace_with[$i]}"
        if [[ "$aur_helper" == "paru" ]] && command -v paru >/dev/null 2>&1; then
          runuser -u "$real_user" -- paru -S --needed --noconfirm "${replace_with[$i]}" 2>/dev/null || true
        elif [[ "$aur_helper" == "shelly" ]] && command -v shelly >/dev/null 2>&1; then
          # shelly install = repos, shelly install aur = AUR
          # --needed skips already-installed packages (idempotent re-runs)
          # --no-confirm makes shelly non-interactive (no prompts)
          if pacman -Si "${replace_with[$i]}" >/dev/null 2>&1; then
            runuser -u "$real_user" -- shelly install "${replace_with[$i]}" --needed --no-confirm 2>/dev/null || true
          else
            runuser -u "$real_user" -- shelly install aur "${replace_with[$i]}" --needed --no-confirm 2>/dev/null || true
          fi
        else
          sudo pacman -S --needed --noconfirm "${replace_with[$i]}" 2>/dev/null || \
            echo "  warning: ${replace_with[$i]} not in repos; install an AUR helper (ucli devmode) for AUR packages" >&2
        fi
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

# ucli's own runtime first: gum (menus) and python-pipx (gext). `base` installs
# these too, but the fresh-install flow is setup-desktop -> devmode -> apps, so
# they have to land here as well or the gext step below fails.
if [[ -x "$script_dir/install-packages.sh" ]]; then
  "$script_dir/install-packages.sh" ucli-runtime || true
fi

# Fonts and themes needed by backed-up settings (Ghostty, Adwaita, Papirus)
if [[ -x "$script_dir/install-packages.sh" ]]; then
  "$script_dir/install-packages.sh" fonts
fi

# The desktop's own apps: firefox (the configured browser, on every desktop) plus
# the terminal that desktop is configured for — ghostty on gnome/hyprland, kitty
# on kde. The DE install above only covers DE packages and the replacement
# matrix, and it never installs a terminal it would then have two of.
if [[ -x "$script_dir/install-packages.sh" ]]; then
  "$script_dir/install-packages.sh" essentials || true
fi

# The shell tier (zsh + oh-my-zsh + plugins + starship) belongs to this step too:
# `ucli setup-system` is the only machine-setup command a fresh install runs, so
# if the shell waited for `ucli cli` you would boot into bash with no prompt.
# Packages as root, then the user-owned part (omz, plugin clones, chsh) as the
# real user — oh-my-zsh must never end up root-owned.
if [[ -x "$script_dir/install-packages.sh" ]]; then
  "$script_dir/install-packages.sh" shell-tools || true
fi

# Deploy the dotfiles that only make sense now that the desktop exists: ~/.zshrc,
# starship, ~/.config/<terminal>, ~/.config/firefox. .chezmoiignore checks for the
# programs with lookPath, so a TTY-only box gets none of them — this is the apply
# that makes them appear. Runs as the real user (root-owned $HOME would be wrong)
# and is not fatal: a machine without chezmoi initialized still gets a desktop.
if [[ -x "$(command -v chezmoi || true)" ]] && [[ -d "$real_home/.local/share/chezmoi" ]]; then
  echo "Applying dotfiles for $real_user (shell, terminal, browser configs) ..."
  runuser -u "$real_user" -- env HOME="$real_home" chezmoi apply -v \
    || echo "warning: chezmoi apply failed; run 'ucli chezmoi-apply' as $real_user" >&2
else
  echo "note: chezmoi not initialized for $real_user; run 'ucli chezmoi-apply' after bootstrap." >&2
fi

if [[ -x "$script_dir/install-shell.sh" ]]; then
  echo "Setting up the shell (oh-my-zsh, plugins, starship) for $real_user ..."
  runuser -u "$real_user" -- env UCLI_SKIP_PACKAGES=1 "$script_dir/install-shell.sh" \
    || echo "warning: shell setup failed; run 'ucli cli' as $real_user" >&2
fi

# GNOME extensions are handled by the extension-set script via gext.
# Ensure gext is installed (via pipx) before installing extensions.
if [[ "$desktop" == "gnome" ]]; then
  # Add user's pipx bin to PATH when running as root
  if [[ "$EUID" -eq 0 ]] && [[ -d "$real_home/.local/bin" ]]; then
    export PATH="$real_home/.local/bin:$PATH"
  fi
  if ! command -v gext >/dev/null 2>&1; then
    echo "gext (gnome-extensions-cli) not found; installing via pipx ..."
    if command -v pipx >/dev/null 2>&1; then
      runuser -u "$real_user" -- pipx install gnome-extensions-cli
      export PATH="$real_home/.local/bin:$PATH"
    else
      echo "  error: pipx not found. Run 'sudo pacman -S --needed python-pipx' first, then 'ucli install-gnome-extensions-cli'" >&2
      exit 1
    fi
  fi
  # System extensions first, then user/personal overrides.
  "$script_dir/install-gnome-extension-set.sh" system || true
  "$script_dir/install-gnome-extension-set.sh" overrides || true
fi

# Create a snapshot capturing the DE-installed state. Not fatal: on a machine
# where `ucli setup-snapshots` has not run yet there is no snapper config, and
# failing the whole desktop setup over a restore point would be silly.
"$script_dir/../system/snapshot-fresh-install.sh" "$desktop Setup" \
  || echo "warning: snapshot skipped (no snapper config yet — run 'ucli setup-snapshots')" >&2

echo "Desktop $desktop installed and snapshot created."
echo "Next: log out and back in (zsh + extensions), then 'ucli devmode' and 'ucli apps'."
echo "To backup GNOME settings: ucli backup-gnome-settings"
