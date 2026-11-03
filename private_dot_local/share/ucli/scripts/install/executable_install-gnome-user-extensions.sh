#!/usr/bin/env bash
set -euo pipefail

# Installs GNOME Shell extensions that are not handled by pacman/paru arrays,
# using gnome-extensions-cli (gext).
#
# - BetterTrayIcons (pk 9975)
# - user-accent-colors / ChromaLeon (pk 10070)
#
# Source: https://github.com/essembeh/gnome-extensions-cli

if ! command -v gext >/dev/null 2>&1; then
  echo "gext (gnome-extensions-cli) not found" >&2
  echo "  run: ucli install-gnome-extensions-cli" >&2
  exit 1
fi

echo "installing BetterTrayIcons (pk 9975) ..."
gext install 9975 >/dev/null 2>&1 || echo "warning: could not install BetterTrayIcons" >&2
gext enable BetterTrayIcons@nexaknight.com >/dev/null 2>&1 || echo "warning: could not enable BetterTrayIcons" >&2

echo "installing user-accent-colors / ChromaLeon (pk 10070) ..."
gext install 10070 >/dev/null 2>&1 || echo "warning: could not install user-accent-colors" >&2
gext enable user-accent-colors@fabito02 >/dev/null 2>&1 || echo "warning: could not enable user-accent-colors" >&2

echo "User-managed GNOME extensions installed. Log out/in if GNOME does not show them immediately."