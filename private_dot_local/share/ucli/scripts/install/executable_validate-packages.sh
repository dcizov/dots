#!/usr/bin/env bash
set -euo pipefail

usage() { echo 'usage: validate-packages.sh [--all]'; }
while (($#)); do
  case "$1" in
    --all) shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HOME/.config/ucli/packages.bash"

status=0
package_arrays=(
  BOOTSTRAP ZSH SYSTEM_CORE_TOOLS SYSTEM_QOL_TOOLS CPU_INTEL CPU_AMD GPU_AMD GPU_INTEL GPU_NVIDIA
  SYSTEM_SUPPORT BOOT_SUPPORT SNAPSHOT_LIMINE FONTS_THEMES CLI DEV_CLI DEV GAMING
  DESKTOP_GNOME_BASE GNOME_SYSTEM_EXTENSION_PACKAGES GNOME_APP_OVERRIDES GNOME_SHELL_OVERRIDES
  DESKTOP_HYPRLAND_BASE DESKTOP_HYPRLAND_ADDITIONS DESKTOP_KDE_BASE DESKTOP_KDE_ADDITIONS
  APPS MANUAL_AUR
)
extension_pk_arrays=(GNOME_SYSTEM_EXTENSION_PKS GNOME_OVERRIDE_EXTENSION_PKS)

aur_exists() {
  local pkg="$1"
  # Primary: AUR RPC API (fast, structured).
  if python3 - "$pkg" <<'PY' >/dev/null 2>&1
import json, sys, urllib.parse, urllib.request
pkg = sys.argv[1]
url = "https://aur.archlinux.org/rpc/v5/info?" + urllib.parse.urlencode({"arg[]": pkg})
with urllib.request.urlopen(url, timeout=15) as response:
    data = json.load(response)
for result in data.get("results", []):
    if result.get("Name") == pkg:
        sys.exit(0)
sys.exit(1)
PY
  then
    return 0
  fi
  # Fallback: git ls-remote (works when the API is down or rate-limited).
  if command -v git >/dev/null 2>&1; then
    git ls-remote "https://aur.archlinux.org/${pkg}.git" >/dev/null 2>&1
    return $?
  fi
  return 1
}

extension_pk_exists() {
  local pk="$1"
  # Primary: extensions.gnome.org API
  if curl -fsL "https://extensions.gnome.org/extension-info/?pk=${pk}" >/dev/null 2>&1; then
    return 0
  fi
  # Fallback: validate that the pk is a positive integer (all GNOME extension
  # primary keys are numeric). This avoids false negatives when the API is down.
  [[ "$pk" =~ ^[0-9]+$ ]]
}

validate_item() {
  local item="$1"
  [[ -n "$item" ]] || return 0
  if pacman -Si "$item" >/dev/null 2>&1; then echo "OK repo package: $item"; return 0; fi
  if pacman -Sgq "$item" >/dev/null 2>&1; then echo "OK repo group:   $item"; return 0; fi
  if aur_exists "$item"; then echo "OK AUR:          $item"; return 0; fi
  echo "MISSING:         $item"
  return 1
}

validate_package_array() {
  local name="$1" items=() item
  eval 'items=("${'"$name"'[@]:-}")'
  echo "==> checking package array: $name"
  for item in "${items[@]}"; do validate_item "$item" || status=1; done
}

validate_extension_pk_array() {
  local name="$1" items=() pk
  eval 'items=("${'"$name"'[@]:-}")'
  echo "==> checking GNOME extension API array: $name"
  for pk in "${items[@]}"; do
    if extension_pk_exists "$pk"; then echo "OK extension pk: $pk"; else echo "MISSING extension pk: $pk"; status=1; fi
  done
}

for array in "${package_arrays[@]}"; do validate_package_array "$array"; done
for array in "${extension_pk_arrays[@]}"; do validate_extension_pk_array "$array"; done

exit "$status"
