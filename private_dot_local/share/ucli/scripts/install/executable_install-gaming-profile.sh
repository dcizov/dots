#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# shellcheck source=/dev/null
source "$real_home/.config/ucli/scripts/lib/detect.sh"

distro="$(ucli_norm "$(detect_distro)")"
if [[ "$distro" == "cachyos" ]]; then
  echo "CachyOS detected: gaming packages are normally handled by CachyOS Hello. Skipping."
  exit 0
fi

"$script_dir/install-packages.sh" --force gaming
"$script_dir/install-flatpaks.sh" gaming