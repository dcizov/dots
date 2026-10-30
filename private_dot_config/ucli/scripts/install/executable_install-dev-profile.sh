#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/install-packages.sh" dev
"$script_dir/install-flatpaks.sh" dev

if command -v codium >/dev/null 2>&1 && [[ -x "$script_dir/install-vscodium-extensions.sh" ]]; then
  "$script_dir/install-vscodium-extensions.sh" || true
fi
