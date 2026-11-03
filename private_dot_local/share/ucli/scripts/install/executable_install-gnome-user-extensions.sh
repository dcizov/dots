#!/usr/bin/env bash
set -euo pipefail

# Installs user-managed GNOME Shell extensions using gnome-extensions-cli (gext).
#
# This is a thin wrapper around install-gnome-extension-set.sh overrides,
# kept for backwards compatibility with the _user-extensions recipe.
#
# All extensions are installed via gext from extensions.gnome.org —
# no GitHub source builds, no manual curl downloads.
#
# Source: https://github.com/essembeh/gnome-extensions-cli

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v gext >/dev/null 2>&1; then
  echo "gext (gnome-extensions-cli) not found" >&2
  echo "  run: ucli install-gnome-extensions-cli" >&2
  exit 1
fi

echo "Installing user-managed GNOME extensions via gext ..."
"$script_dir/install-gnome-extension-set.sh" overrides

echo "User-managed GNOME extensions installed via gext."