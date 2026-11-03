#!/usr/bin/env bash
set -euo pipefail

# Install/enable GNOME system extensions from packages.bash arrays.
#
# Usage:
#   install-gnome-extension-set.sh system   # default system extensions (from GNOME_SYSTEM_EXTENSION_PACKAGES)
#   install-gnome-extension-set.sh overrides # app overrides (from GNOME_APP_OVERRIDES + GNOME_SHELL_OVERRIDES)
#
# Package-based extensions are installed via pacman/paru by install-packages.sh
# when the desktop mode includes them. This script only ensures they are
# enabled in GNOME Shell and installs any non-repo extensions via the
# extensions.gnome.org API (by primary key).

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

# shellcheck source=/dev/null
source "$real_home/.config/ucli/packages.bash"
# shellcheck source=/dev/null
source "$real_home/.config/ucli/scripts/lib/detect.sh"

if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "gnome-extensions not found; install gnome-shell-extensions first" >&2
  exit 1
fi

# extensions.gnome.org API install by primary key.
# NOTE: no trap here — tmp is cleaned up explicitly at each return
# point because `set -u` would fail on an EXIT trap referencing a
# `local` variable that's out of scope by script exit time.
install_extension_by_pk() {
  local pk="$1" uuid="$2"
  local tmp
  tmp="$(mktemp -d)"

  echo "downloading extension pk=$pk ..."
  if ! curl -fsL "https://extensions.gnome.org/extension-info/?pk=${pk}" -o "$tmp/info.json" 2>/dev/null; then
    echo "warning: could not fetch extension info for pk=$pk" >&2
    rm -rf "$tmp"
    return 1
  fi

  local download_url
  download_url="$(python3 -c 'import json; d=json.load(open(\"'\"$tmp\"'/info.json\")); print(d.get("download_url",""))' 2>/dev/null || true)"
  if [[ -z "$download_url" ]]; then
    echo "warning: no download_url for pk=$pk" >&2
    rm -rf "$tmp"
    return 1
  fi

  # download_url is relative to extensions.gnome.org
  case "$download_url" in
    http*) ;;
    *) download_url="https://extensions.gnome.org${download_url}" ;;
  esac

  if ! curl -fsL "$download_url" -o "$tmp/extension.zip" 2>/dev/null; then
    echo "warning: could not download extension pk=$pk" >&2
    rm -rf "$tmp"
    return 1
  fi

  gnome-extensions install "$tmp/extension.zip" --force 2>/dev/null || true

  if [[ -n "$uuid" ]]; then
    gnome-extensions enable "$uuid" 2>/dev/null || echo "warning: could not enable $uuid" >&2
  fi

  rm -rf "$tmp"
}

case "$mode" in
  system)
    echo "enabling system GNOME extensions ..."
    for uuid in "${GNOME_SYSTEM_EXTENSION_UUIDS[@]:-}"; do
      gnome-extensions enable "$uuid" 2>/dev/null || echo "warning: could not enable $uuid (may need shell restart)" >&2
    done
    # Install non-repo extensions by API key
    for i in "${!GNOME_SYSTEM_EXTENSION_PKS[@]}"; do
      install_extension_by_pk "${GNOME_SYSTEM_EXTENSION_PKS[$i]}" "${GNOME_SYSTEM_EXTENSION_UUIDS[$i]:-}"
    done
    ;;
  overrides)
    echo "installing GNOME app overrides ..."
    # App overrides are pacman packages installed by install-packages.sh apps mode.
    # Shell override themes are also pacman packages.
    for uuid in "${GNOME_OVERRIDE_EXTENSION_UUIDS[@]:-}"; do
      gnome-extensions enable "$uuid" 2>/dev/null || echo "warning: could not enable $uuid (may need shell restart)" >&2
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