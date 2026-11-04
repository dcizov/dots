#!/usr/bin/env bash
# Install firefox-gnome-theme for GNOME desktop integration.
# Only runs when desktop is gnome and firefox is installed.
#
# Downloads the latest XPI from:
#   https://github.com/rafaelmardojai/firefox-gnome-theme/releases/latest
# and installs it via `firefox --install-extension`.
#
# Source: https://github.com/rafaelmardojai/firefox-gnome-theme
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo (from setup-desktop.sh), use the invoking user's home
# so the theme is installed in the user's Firefox profile, not root's.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# Only install if firefox is present
if ! command -v firefox >/dev/null 2>&1; then
  echo "firefox not installed; skipping firefox-gnome-theme" >&2
  exit 0
fi

THEME_XPI="$real_home/.mozilla/extensions/firefox-gnome-theme@rafaelmardojai.xpi"
THEME_DIR="$(dirname "$THEME_XPI")"
mkdir -p "$THEME_DIR"

# Download latest release XPI from GitHub
LATEST_XPI="https://github.com/rafaelmardojai/firefox-gnome-theme/releases/latest/download/firefox-gnome-theme.xpi"

echo "Downloading firefox-gnome-theme ..."
if ! curl -fsSL -o "$THEME_XPI" "$LATEST_XPI"; then
  echo "warning: could not download firefox-gnome-theme" >&2
  exit 0
fi

# Install via Firefox headless mode
echo "Installing firefox-gnome-theme into Firefox ..."
if ! firefox --headless --install-extension "$THEME_XPI" 2>/dev/null; then
  echo "warning: firefox --install-extension failed" >&2
  echo "  XPI saved to: $THEME_XPI" >&2
  echo "  Install manually via Firefox Add-ons Manager" >&2
fi

echo "firefox-gnome-theme installed."