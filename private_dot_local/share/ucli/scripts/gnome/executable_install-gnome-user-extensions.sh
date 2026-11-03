#!/usr/bin/env bash
set -euo pipefail

# Installs GNOME Shell extensions that are intentionally not handled by pacman/paru arrays:
# - BetterTrayIcons from upstream GitHub source (clone + make install)
# - ChromaLeon/User Accent Colors from extensions.gnome.org via GNOME's local extension installer

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/install-better-tray-icons.sh" --update --enable
"$script_dir/install-gnome-extension.sh" --pk 10070 --enable --force

echo "User-managed GNOME extensions installed. Log out/in if GNOME does not show them immediately."
