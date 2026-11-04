#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# shellcheck source=/dev/null
source "$real_home/.config/ucli/scripts/lib/detect.sh"

# base = a working machine: packages, system tools, desktop, fonts. The shell
# experience (oh-my-zsh, plugins, default shell) is the CLI tier: `ucli cli`.
"$script_dir/install-packages.sh" base
"$script_dir/install-flatpaks.sh" base