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

# Install desktop packages via the package resolver.
"$script_dir/install-packages.sh" desktop --desktop="$desktop"

# GNOME extensions are handled by the extension-set script.
if [[ "$desktop" == "gnome" ]]; then
  "$script_dir/install-gnome-extension-set.sh" system || true
fi

# Create a snapshot capturing the DE-installed state.
"$script_dir/../system/snapshot-fresh-install.sh" "$desktop Setup"

echo "Desktop $desktop installed and snapshot created."
echo "Next: run 'ucli setup-snapshots' (if not already done), then 'ucli devmode' and 'ucli apps'."
