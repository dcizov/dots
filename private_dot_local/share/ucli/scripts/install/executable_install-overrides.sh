#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HOME/.config/ucli/scripts/lib/detect.sh"

desktop="$(detect_desktop 2>/dev/null || echo none)"
"$script_dir/install-packages.sh" apps
"$script_dir/install-flatpaks.sh" apps

if [[ "$desktop" == "gnome" ]]; then
  "$script_dir/install-gnome-extension-set.sh" overrides || true
fi
