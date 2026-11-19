#!/usr/bin/env bash
set -euo pipefail
# `ucli gaming`: the opt-in gaming packages and Flatpaks. On CachyOS this is
# CachyOS Hello's job (its gaming meta packages), so nothing is done there.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/detect.sh
source "$script_dir/../lib/detect.sh"

distro="$(ucli_norm "$(detect_distro)")"
if [[ "$distro" == "cachyos" ]]; then
  echo "CachyOS detected: gaming packages are normally handled by CachyOS Hello. Skipping."
  exit 0
fi

"$script_dir/install-packages.sh" --force gaming
"$script_dir/install-flatpaks.sh" gaming