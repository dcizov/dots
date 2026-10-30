#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/install-packages.sh" dev
"$script_dir/install-flatpaks.sh" dev

if command -v codium >/dev/null 2>&1 && [[ -x "$script_dir/install-vscodium-extensions.sh" ]]; then
  "$script_dir/install-vscodium-extensions.sh" || true
fi

# The dev box is part of the dev profile: create it, or bring an existing one
# in line with the current dotfiles commit. Non-fatal — a missing podman or
# distrobox should not fail the package install.
RECONCILE="$HOME/.config/ucli/scripts/devbox/devbox-reconcile.sh"
if command -v distrobox >/dev/null 2>&1 && [[ -x "$RECONCILE" ]]; then
  "$RECONCILE" || printf 'warning: devbox reconcile failed — run: ucli devbox-reconcile\n' >&2
fi
