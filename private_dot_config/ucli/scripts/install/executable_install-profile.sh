#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/../lib/detect.sh"

"$script_dir/install-packages.sh" base
"$script_dir/install-shell.sh"
"$script_dir/install-flatpaks.sh" base

if [[ "$(detect_desktop 2>/dev/null || echo none)" == "gnome" ]]; then
  "$script_dir/install-gnome-extension-set.sh" system || true
fi
