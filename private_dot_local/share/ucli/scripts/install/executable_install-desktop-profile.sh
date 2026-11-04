#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# `desktop` mode detects the desktop itself (--desktop= owner), so nothing here
# guesses at it: this script is the package half of the desktop step only.
"$script_dir/install-packages.sh" desktop
# Fonts and themes are referenced by the shipped configs (ghostty font, adw-gtk3,
# Adwaita icons)
"$script_dir/install-packages.sh" fonts