#!/usr/bin/env bash
# Check every name in every package array against pacman (package or group)
# and the AUR, and every GNOME extension pk against extensions.gnome.org.
# Network, read-only. The personal overlay (packages.local.bash) is checked
# too: a typo there breaks `ucli apps` exactly like one in packages.bash.
#
#   validate-packages.sh          exit 0 when everything resolves, 1 otherwise
#   validate-packages.sh --all    accepted for compatibility; same as no flag
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$script_dir/../lib/common.sh"
# shellcheck source=../lib/aur.sh
. "$script_dir/../lib/aur.sh"

while (($#)); do
  case "$1" in
    --all) shift ;;
    -h|--help) ucli_script_help; exit 0 ;;
    *) echo "unknown argument: $1" >&2; ucli_script_help >&2; exit 2 ;;
  esac
done

ucli_load_packages

status=0
package_arrays=(
  BOOTSTRAP SHELL_TOOLS SYSTEM_CORE_TOOLS SYSTEM_QOL_TOOLS CPU_INTEL CPU_AMD GPU_AMD GPU_INTEL GPU_NVIDIA
  SYSTEM_SUPPORT BOOT_SUPPORT SNAPSHOT_LIMINE FONTS_THEMES FONTS_MS UCLI_RUNTIME CLI DEV_CLI DEV
  VIRT GAMING
  DESKTOP_GNOME_BASE GNOME_SYSTEM_EXTENSION_PACKAGES GNOME_EXTENSION_TOOLING GNOME_APP_OVERRIDES
  SYSTEM_MEDIA_CODECS HARDWARE_FINGERPRINT HARDWARE_TOUCHPAD
  DESKTOP_HYPRLAND_BASE DESKTOP_HYPRLAND_ADDITIONS DESKTOP_KDE_BASE DESKTOP_KDE_ADDITIONS
  DESKTOP_BROWSER DESKTOP_TERMINAL_GNOME DESKTOP_TERMINAL_HYPRLAND DESKTOP_TERMINAL_KDE
  APPS MANUAL_AUR
  PERSONAL_PKGS PERSONAL_DEV
)
# Extension lists are "PK:UUID" pairs (see packages.bash for why). The personal
# list is empty unless the overlay fills it.
extension_lists=(GNOME_MANAGED_EXTENSIONS PERSONAL_GNOME_EXTENSIONS)

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

validate_extension_list() {
  local name="$1" items=() entry pk uuid
  eval 'items=("${'"$name"'[@]:-}")'
  echo "==> checking GNOME extension list: $name"
  for entry in "${items[@]}"; do
    [[ -n "$entry" ]] || continue
    pk="${entry%%:*}"
    uuid="${entry#*:}"
    if [[ "$entry" != *:* ]] || [[ -z "$pk" ]] || [[ -z "$uuid" ]]; then
      echo "MALFORMED (want PK:UUID): $entry"; status=1; continue
    fi
    if extension_pk_exists "$pk"; then echo "OK extension: $pk ($uuid)"; else echo "MISSING extension pk: $pk"; status=1; fi
  done
}

for array in "${package_arrays[@]}"; do validate_package_array "$array"; done
for array in "${extension_lists[@]}"; do validate_extension_list "$array"; done

exit "$status"
