#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# shellcheck source=/dev/null
source "$real_home/.config/ucli/scripts/lib/detect.sh"

# Detect desktop for gnome-only blocks (firefox-gnome-theme, gnome extensions)
desktop="$(detect_desktop 2>/dev/null || echo none)"

"$script_dir/install-packages.sh" apps
"$script_dir/install-flatpaks.sh" apps

# Firefox Betterfox user.js — applies on all desktops (Firefox is desktop-agnostic)
# Requires Firefox to have been run at least once (profile must exist)
"$script_dir/install-firefox-betterfox.sh" || true

# Firefox extensions (regular) — installed during ucli apps
# Requires Firefox to have been run at least once (profile must exist)
"$script_dir/install-firefox-extensions.sh" "$real_home/.config/firefox/extensions.txt" || true

if [[ "$desktop" == "gnome" ]]; then
  "$script_dir/install-gnome-extension-set.sh" overrides || true
  # Firefox GNOME theme — only makes sense on GNOME desktop
  # Requires Firefox to have been run at least once (profile must exist)
  "$script_dir/install-firefox-gnome-theme.sh" || true
fi