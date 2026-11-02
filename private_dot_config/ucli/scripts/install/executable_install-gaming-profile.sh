#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/../lib/detect.sh"

distro="$(ucli_norm "$(detect_distro)")"
if [[ "$distro" == "cachyos" ]]; then
  echo "CachyOS detected: gaming packages are normally handled by CachyOS Hello. Skipping."
  exit 0
fi

"$script_dir/install-packages.sh" --force gaming
"$script_dir/install-flatpaks.sh" gaming
