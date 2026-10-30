#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/../lib/detect.sh"

desktop="$(detect_desktop 2>/dev/null || echo none)"
"$script_dir/install-packages.sh" desktop

if [[ "$desktop" == "gnome" ]]; then
  "$script_dir/install-gnome-extension-set.sh" system || true
fi
