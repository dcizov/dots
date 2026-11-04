#!/usr/bin/env bash
# Install firefox-gnome-theme using the official install script.
# Only runs when desktop is gnome and firefox is installed.
#
# Clones the theme repo, then runs scripts/install.sh as the real user
# so the theme is integrated into the user's Firefox profile(s).
#
# Source: https://github.com/rafaelmardojai/firefox-gnome-theme
# Install docs: https://github.com/rafaelmardojai/firefox-gnome-theme/blob/master/README.md#installation-scripts
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

# Clone the theme repo to a temp location
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Cloning firefox-gnome-theme ..."
if ! git clone --depth=1 https://github.com/rafaelmardojai/firefox-gnome-theme.git "$TMPDIR/firefox-gnome-theme" 2>/dev/null; then
  echo "warning: could not clone firefox-gnome-theme repo" >&2
  exit 0
fi

INSTALL_SCRIPT="$TMPDIR/firefox-gnome-theme/scripts/install.sh"
PROFILE_DIR="$real_home/.mozilla/firefox"

if [[ ! -x "$INSTALL_SCRIPT" ]]; then
  chmod +x "$INSTALL_SCRIPT"
fi

# Run install.sh as the real user — it auto-detects profiles in $PROFILE_DIR
# and integrates userChrome.css/userContent.css/user.js for each one.
echo "Installing firefox-gnome-theme into Firefox profile(s) ..."
if [[ "$EUID" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
  runuser -u "$real_user" -- env HOME="$real_home" "$INSTALL_SCRIPT" -f "$PROFILE_DIR" 2>/dev/null || \
    echo "warning: firefox-gnome-theme install script failed" >&2
else
  "$INSTALL_SCRIPT" -f "$PROFILE_DIR" 2>/dev/null || \
    echo "warning: firefox-gnome-theme install script failed" >&2
fi

echo "firefox-gnome-theme installed."