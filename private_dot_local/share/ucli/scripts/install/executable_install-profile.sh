#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# shellcheck source=/dev/null
source "$real_home/.config/ucli/scripts/lib/detect.sh"

"$script_dir/install-packages.sh" base
"$script_dir/install-shell.sh"
"$script_dir/install-flatpaks.sh" base

if [[ "$(detect_desktop 2>/dev/null || echo none)" == "gnome" ]]; then
  "$script_dir/install-gnome-extension-set.sh" system || true
  "$script_dir/install-gnome-extension-set.sh" overrides || true
fi