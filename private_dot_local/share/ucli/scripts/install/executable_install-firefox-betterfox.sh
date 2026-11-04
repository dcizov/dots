#!/usr/bin/env bash
# Install Betterfox user.js into every Firefox profile.
#
# Copies the vendored user.js (Betterfox v154 + user overrides) into each
# profile directory under ~/.mozilla/firefox/, so the config applies on the
# next Firefox restart.
#
# Works on all desktops (gnome, hyprland, kde) — Firefox is desktop-agnostic.
#
# Source: https://github.com/yokoffing/Betterfox
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, use the invoking user's home
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

if ! command -v firefox >/dev/null 2>&1; then
  echo "firefox not installed; skipping Betterfox" >&2
  exit 0
fi

PROFILE_DIR="$real_home/.mozilla/firefox"
SOURCE_USER_JS="$real_home/.config/firefox/user.js"

if [[ ! -d "$PROFILE_DIR" ]]; then
  echo "no Firefox profile found at $PROFILE_DIR; skipping Betterfox" >&2
  echo "  launch Firefox once to create a profile, then re-run: ucli apps" >&2
  exit 0
fi

if [[ ! -f "$SOURCE_USER_JS" ]]; then
  echo "Betterfox user.js not found at $SOURCE_USER_JS; skipping" >&2
  exit 0
fi

# profiles.ini lists all profiles; copy user.js into each one that has a directory
echo "Installing Betterfox user.js into Firefox profiles ..."

while IFS= read -r line; do
  # Parse Path= line from profiles.ini
  path="${line#Path=}"
  if [[ "$path" != "$line" ]]; then
    # IsAbsolute=1 means absolute path; otherwise relative to PROFILE_DIR
    is_abs=""
    # Read the next lines to check IsAbsolute — simpler: just check if path starts with /
    if [[ "$path" == /* ]]; then
      prof_dir="$path"
    else
      prof_dir="$PROFILE_DIR/$path"
    fi
    if [[ -d "$prof_dir" ]]; then
      cp -f "$SOURCE_USER_JS" "$prof_dir/user.js"
      echo "  installed to $prof_dir/user.js"
    fi
  fi
done < <(grep '^Path=' "$PROFILE_DIR/profiles.ini" 2>/dev/null || true)

echo "Betterfox user.js installed. Restart Firefox to apply."