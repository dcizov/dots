#!/usr/bin/env bash
# Install firefox-gnome-theme using the official install script.
# Only runs when desktop is gnome and firefox is installed and has a profile.
#
# Clones the theme repo, then runs scripts/install.sh as the real user
# so the theme is integrated into the user's Firefox profile(s).
#
# Source: https://github.com/rafaelmardojai/firefox-gnome-theme
# Install docs: https://github.com/rafaelmardojai/firefox-gnome-theme/blob/master/README.md#installation-scripts
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$script_dir/../lib/common.sh"
# Profile location (147+ XDG vs legacy ~/.mozilla) comes from lib/firefox.sh.
# shellcheck source=../lib/firefox.sh
source "$script_dir/../lib/firefox.sh"

case "${1:-}" in
  "") ;;
  -h|--help) ucli_script_help; exit 0 ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

# When run via sudo (from setup-desktop.sh), the theme goes into the invoking
# user's Firefox profile, not root's.
real_user="$(ucli_real_user)"
real_home="$(ucli_real_home)"

if ! command -v firefox >/dev/null 2>&1; then
  echo "firefox not installed; skipping firefox-gnome-theme" >&2
  exit 0
fi

PROFILE_DIR="$(fx_profile_root "$real_home")"

# install.sh integrates into existing profiles, so there must be one.
if [[ ! -d "$PROFILE_DIR" ]]; then
  echo "no Firefox profile found ($(fx_short_root "$PROFILE_DIR" "$real_home")); skipping firefox-gnome-theme" >&2
  echo "  launch Firefox once to create a profile, then re-run: ucli apps" >&2
  exit 0
fi

# A work dir of our own — not $TMPDIR, which every tool below reads.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "Cloning firefox-gnome-theme ..."
if ! git clone --depth=1 https://github.com/rafaelmardojai/firefox-gnome-theme.git "$workdir/firefox-gnome-theme" 2>/dev/null; then
  echo "warning: could not clone firefox-gnome-theme repo" >&2
  exit 0
fi

INSTALL_SCRIPT="$workdir/firefox-gnome-theme/scripts/install.sh"
[[ -x "$INSTALL_SCRIPT" ]] || chmod +x "$INSTALL_SCRIPT"

# Run install.sh as the real user — it finds the profiles in $PROFILE_DIR and
# integrates userChrome.css/userContent.css/user.js into each. Under sudo the
# clone is root's (mktemp -d is mode 0700), so hand it over first: the user
# could not even read it, and the install failed on every setup-desktop run.
echo "Installing firefox-gnome-theme into Firefox profile(s) ..."
if [[ "${EUID:-$(id -u)}" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
  chown -R "$real_user" "$workdir"
  run_install() { runuser -u "$real_user" -- env HOME="$real_home" "$INSTALL_SCRIPT" -f "$PROFILE_DIR"; }
else
  run_install() { "$INSTALL_SCRIPT" -f "$PROFILE_DIR"; }
fi
if ! run_install; then
  echo "warning: firefox-gnome-theme install script failed (see above)" >&2
  exit 1
fi

echo "firefox-gnome-theme installed."
