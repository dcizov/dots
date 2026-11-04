#!/usr/bin/env bash
set -euo pipefail

# Reverse what chezmoi/ucli deployed in this user's home directory.
#
# Removes chezmoi-managed dotfiles, the ucli wrapper, and packages installed
# by ucli cli/devmode/gaming. Does NOT remove system packages installed
# outside of ucli (e.g. bootstrap packages, desktop environment).
#
# Usage:
#   uninstall.sh [--yes]   # skip confirmation prompts
#
# Safe to re-run; missing paths are skipped.

yes_flag=0
take_snapshot=1
for arg in "$@"; do
  case "$arg" in
    --yes|-y) yes_flag=1 ;;
    --no-snapshot) take_snapshot=0 ;;
    --help|-h)
      cat <<'USAGE'
usage: uninstall.sh [--yes] [--no-snapshot]

Remove chezmoi-managed dotfiles, ucli, and ucli-installed packages.
  --yes          skip confirmation prompts
  --no-snapshot  do not take a Snapper snapshot first
USAGE
      exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

confirm() {
  local prompt="$1"
  (( yes_flag )) && return 0
  read -r -p "$prompt [y/N] " ans
  [[ "$ans" == y || "$ans" == Y || "$ans" == yes ]]
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HOME/.config/ucli/packages.bash"

HOME_TARGETS=(
  # chezmoi-managed dotfiles (private_dot_* -> ~/.*, dot_* -> ~/.*)
  "$HOME/.zshrc"
  "$HOME/.bash_profile"
  "$HOME/.atuin"
  "$HOME/.vscode-oss"
  "$HOME/.config/atuin"
  "$HOME/.config/bat"
  "$HOME/.config/dev-services"
  "$HOME/.config/direnv"
  "$HOME/.config/distrobox"
  "$HOME/.config/fd"
  "$HOME/.config/ghostty"
  "$HOME/.config/glow"
  "$HOME/.config/kitty"
  "$HOME/.config/mise"
  "$HOME/.config/restic"
  "$HOME/.config/ripgrep"
  "$HOME/.config/starship.toml"
  # Includes ucli's Firefox sources (user.js, extension lists). Those are NOT a
  # Firefox path: profiles live in ~/.config/mozilla/firefox (FF 147+) or
  # ~/.mozilla/firefox (legacy) and are deliberately left alone here.
  "$HOME/.config/ucli"
  "$HOME/.config/VSCodium"
  "$HOME/.config/zsh"
  "$HOME/.local/bin/ucli"
  # kwi (KDE's terminal) runtime data, if it ever ships one
  "$HOME/.local/share/kwi"
  # chezmoi runtime state
  "$HOME/.local/share/chezmoi"
  "$HOME/.config/chezmoi"
  "$HOME/.chezmoi.toml"
  # oh-my-zsh + plugins (cloned by install-shell.sh, not chezmoi-managed)
  "$HOME/.oh-my-zsh"
)

echo "The following paths will be removed from $HOME:"
for t in "${HOME_TARGETS[@]}"; do
  if [[ -e "$t" ]]; then
    printf '  %s\n' "$t"
  fi
done

echo
if ! confirm "Remove all listed paths?"; then
  echo "aborted."
  exit 0
fi

# Restore point before deleting anything. Uninstall removes packages and dotfiles
# wholesale, so a snapshot is the difference between "try again" and "reinstall".
# One snapshot script decides whether a restore point is possible; this only
# forwards the flag (and does nothing when it is missing, e.g. a broken deploy).
snapshot_script="$script_dir/../system/snapshot-fresh-install.sh"
if (( take_snapshot )) && [[ -x "$snapshot_script" ]]; then
  echo "Creating a snapshot before uninstalling ..."
  sudo "$snapshot_script" "before ucli uninstall" \
    || echo "warning: snapshot failed; continuing anyway (press Ctrl-C now to abort)" >&2
fi

for t in "${HOME_TARGETS[@]}"; do
  if [[ -e "$t" ]]; then
    rm -rf "$t"
    echo "removed: $t"
  fi
done

# Remove packages installed by ucli cli/devmode/gaming (repo packages only).
echo
echo "removing ucli-installed pacman packages ..."
pkgs_to_remove=()
for p in "${UCLI_RUNTIME[@]:-}" "${CLI[@]:-}" "${DEV_CLI[@]:-}" "${DEV[@]:-}" "${GAMING[@]:-}"; do
  if pacman -Q "$p" >/dev/null 2>&1; then
    pkgs_to_remove+=("$p")
  fi
done

if (( ${#pkgs_to_remove[@]} > 0 )); then
  echo "found installed ucli packages: ${pkgs_to_remove[*]}"
  if confirm "Remove these packages with sudo pacman -Rns?"; then
    sudo pacman -Rns --noconfirm "${pkgs_to_remove[@]}"
  fi
else
  echo "no ucli pacman packages found installed."
fi

# Remove AUR packages installed by ucli (paru packages only).
if command -v paru >/dev/null 2>&1; then
  echo
  echo "checking for ucli AUR packages ..."
  aur_pkgs_to_remove=()
  for p in "${UCLI_RUNTIME[@]:-}" "${CLI[@]:-}" "${DEV_CLI[@]:-}" "${DEV[@]:-}" "${GAMING[@]:-}"; do
    if paru -Q "$p" >/dev/null 2>&1; then
      aur_pkgs_to_remove+=("$p")
    fi
  done
  if (( ${#aur_pkgs_to_remove[@]} > 0 )); then
    echo "found installed ucli AUR packages: ${aur_pkgs_to_remove[*]}"
    if confirm "Remove these AUR packages with paru -Rns?"; then
      paru -Rns --noconfirm "${aur_pkgs_to_remove[@]}"
    fi
  else
    echo "no ucli AUR packages found installed."
  fi
fi

# Remove chezmoi binary if it was installed by bootstrap.
if command -v chezmoi >/dev/null 2>&1 && pacman -Q chezmoi >/dev/null 2>&1; then
  echo
  echo "chezmoi was installed by the bootstrap installer."
  if confirm "Remove chezmoi package?"; then
    sudo pacman -Rns --noconfirm chezmoi
  fi
fi

echo
echo "uninstall complete. You may want to remove the dotfiles repo clone too."