#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# shellcheck source=/dev/null
source "$real_home/.config/ucli/scripts/lib/detect.sh"

# Preflight: the desktop step is the destructive one (packages, chsh, a snapshot
# at the end), so on a machine with no snapper config warn and — on a TTY — ask.
# Same rule as `ucli update`: a pipe/non-TTY proceeds, UCLI_YES=1 proceeds.
if [[ ! -f /etc/snapper/configs/root ]]; then
  echo "warning: no Snapper config found — the desktop step will not be able to"
  echo "         create a restore point first. 'ucli setup-snapshots' sets it up."
  if [[ -t 0 && "${UCLI_YES:-0}" != "1" ]]; then
    read -rp "Continue without snapshots? [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      echo "aborted. run 'ucli setup-snapshots' first."
      exit 1
    fi
  fi
fi

# base = the machine itself: bootstrap, cpu/gpu, system tools, fonts, ucli runtime.
"$script_dir/install-packages.sh" base
"$script_dir/install-flatpaks.sh" base

# The desktop is one owner: setup-desktop.sh installs the DE with the
# replacement matrix, adds ghostty + firefox, installs/enables the GNOME
# extensions and takes a snapshot. Pass the desktop as $1 ("gnome", "kde",
# "hyprland") or leave it empty to let it auto-detect/prompt.
desktop="${1:-}"
if [[ -x "$script_dir/setup-desktop.sh" ]]; then
  if [[ -n "$desktop" ]]; then
    sudo "$script_dir/setup-desktop.sh" "$desktop"
  else
    sudo "$script_dir/setup-desktop.sh"
  fi
else
  echo "warning: setup-desktop.sh missing; install the desktop yourself" >&2
fi