#!/usr/bin/env bash
set -euo pipefail

# Install/enable GNOME Shell extensions using gnome-extensions-cli (gext).
#
# Usage:
#   install-gnome-extension-set.sh system   # default system extensions (from GNOME_SYSTEM_EXTENSION_PACKAGES)
#   install-gnome-extension-set.sh overrides # app overrides (from GNOME_APP_OVERRIDES + GNOME_SHELL_OVERRIDES)
#
# Package-based extensions (gnome-shell-extensions, etc.) are installed via
# pacman/paru by install-packages.sh. This script handles non-repo extensions
# via gext (gnome-extensions-cli) and enables all extensions.
#
# Source: https://github.com/essembeh/gnome-extensions-cli

usage() {
  cat <<'USAGE'
usage: install-gnome-extension-set.sh [system|overrides]

  system   Enable repo-packaged default GNOME system extensions
  overrides Install GNOME app override packages and shell override themes
USAGE
}

mode="${1:-system}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo (from setup-desktop.sh), $HOME is root's home;
# use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# gext is installed by pipx to $real_home/.local/bin; add it to PATH
# when running as root so command -v gext finds it.
if [[ "$EUID" -eq 0 ]] && [[ -d "$real_home/.local/bin" ]]; then
  export PATH="$real_home/.local/bin:$PATH"
fi

# shellcheck source=/dev/null
source "$real_home/.config/ucli/packages.bash"
# shellcheck source=/dev/null
source "$real_home/.config/ucli/scripts/lib/detect.sh"

if ! command -v gext >/dev/null 2>&1; then
  echo "gext (gnome-extensions-cli) not found" >&2
  echo "  run: ucli install-gnome-extensions-cli" >&2
  exit 1
fi

# Run gext as the real user (not root) when invoked via sudo.
# GNOME extensions are per-user; installing as root puts them in root's
# profile, not the user's.
run_gext() {
  if [[ "$EUID" -eq 0 ]] && [[ -n "$SUDO_USER" ]]; then
    runuser -u "$real_user" -- env PATH="$real_home/.local/bin:$PATH" gext "$@"
  else
    gext "$@"
  fi
}

# Install an extension from extensions.gnome.org by primary key, then enable it.
install_extension_by_pk() {
  local pk="$1" uuid="$2"

  echo "installing extension pk=$pk ..."
  if ! run_gext install "$pk" >/dev/null 2>&1; then
    echo "warning: could not install extension pk=$pk" >&2
    return 1
  fi

  if [[ -n "$uuid" ]]; then
    run_gext enable "$uuid" >/dev/null 2>&1 || echo "warning: could not enable $uuid" >&2
  fi
}

case "$mode" in
  system)
    echo "enabling system GNOME extensions ..."
    for uuid in "${GNOME_SYSTEM_EXTENSION_UUIDS[@]:-}"; do
      run_gext enable "$uuid" >/dev/null 2>&1 || echo "warning: could not enable $uuid (may need shell restart)" >&2
    done
    # Install non-repo extensions by primary key via gext
    for i in "${!GNOME_SYSTEM_EXTENSION_PKS[@]}"; do
      install_extension_by_pk "${GNOME_SYSTEM_EXTENSION_PKS[$i]}" "${GNOME_SYSTEM_EXTENSION_UUIDS[$i]:-}"
    done
    ;;
  overrides)
    echo "installing GNOME app overrides ..."
    # App overrides are pacman packages installed by install-packages.sh apps mode.
    # Shell override themes are also pacman packages.
    for uuid in "${GNOME_OVERRIDE_EXTENSION_UUIDS[@]:-}"; do
      run_gext enable "$uuid" >/dev/null 2>&1 || echo "warning: could not enable $uuid (may need shell restart)" >&2
    done
    for i in "${!GNOME_OVERRIDE_EXTENSION_PKS[@]}"; do
      install_extension_by_pk "${GNOME_OVERRIDE_EXTENSION_PKS[$i]}" "${GNOME_OVERRIDE_EXTENSION_UUIDS[$i]:-}"
    done
    ;;
  *)
    echo "unknown mode: $mode (use 'system' or 'overrides')" >&2
    usage
    exit 2
    ;;
esac

echo "done. run 'ucli gnome' or restart GNOME Shell (Alt+F2, r, Enter) to apply."