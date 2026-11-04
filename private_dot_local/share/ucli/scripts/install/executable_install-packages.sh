#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: install-packages.sh [--dry-run] [--yes] [--distro=ID] [--cpu=VENDOR] [--gpu=VENDOR] [--desktop=DE] [--base-desktop] [--additions-only] MODE

Modes:
  base            bootstrap + cpu + gpu + zsh + system-tools + fonts + desktop
  bootstrap       packages needed for chezmoi/ucli bootstrap
  cli             opt-in shell CLI experience
  zsh             zsh plugin packages
  system-tools    system/admin helpers
  cpu             CPU microcode
  gpu             GPU support
  fonts           fonts/themes
  desktop         desktop environment packages
  apps            personal apps and desktop overrides, excluding shell overrides
  shell-overrides explicit shell override packages
  dev-cli         opt-in developer CLI tools
  dev             opt-in dev-cli + developer packages
  gaming          opt-in gaming packages
  snapshot        Btrfs/Snapper/Limine packages
  full            base + cli + dev + gaming(if enabled)

Aliases:
  profile         base
  system          system-tools
  overrides       apps
  full-profile    full

Options:
  --force   bypass role/gaming checks for dev/gaming modes (used by ucli devmode/ucli gaming)

Policy:
  - package names are resolved exactly
  - pacman repo/package group wins
  - AUR is fallback only
  - GNOME extensions that are not repo packages are installed by extensions.gnome.org API scripts, not paru
USAGE
}

dry_run=0
yes_flag=0
base_desktop=0
additions_only=0
force=0
mode=""
distro_override=""
cpu_override=""
gpu_override=""
desktop_override=""

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) dry_run=1 ;;
    --yes|-y) yes_flag=1 ;;
    --base-desktop) base_desktop=1 ;;
    --additions-only) additions_only=1 ;;
    --force) force=1 ;;
    --distro=*) distro_override="${arg#*=}" ;;
    --cpu=*) cpu_override="${arg#*=}" ;;
    --gpu=*) gpu_override="${arg#*=}" ;;
    --desktop=*) desktop_override="${arg#*=}" ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; usage; exit 2 ;;
    *) mode="$arg" ;;
  esac
done

[[ -n "$mode" ]] || { usage; exit 2; }

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# shellcheck source=/dev/null
source "$real_home/.config/ucli/packages.bash"
# shellcheck source=/dev/null
source "$real_home/.config/ucli/scripts/lib/detect.sh"

norm() { tr '[:upper:]' '[:lower:]' <<<"${1:-}" | tr - _; }

distro="$(norm "${distro_override:-$(detect_distro)}")"
cpu="$(norm "${cpu_override:-$(detect_cpu)}")"
gpu="$(norm "${gpu_override:-$(detect_gpu)}")"
desktop="$(norm "${desktop_override:-$(detect_desktop 2>/dev/null || echo none)}")"
role="$(norm "$(detect_role)")"
gaming="$(norm "$(detect_gaming)")"

case "$distro" in
  arch|archlinux|cachyos) ;;
  *) echo "Unsupported distro: $distro" >&2; exit 1 ;;
esac

is_cachyos=0
[[ "$distro" == "cachyos" ]] && is_cachyos=1

selected_packages=()
repo_packages=()
aur_packages=()
missing_packages=()
services=()

add_array() { local name="$1"; eval 'selected_packages+=("${'"$name"'[@]:-}")'; }
add_service_array() { local name="$1"; eval 'services+=("${'"$name"'[@]:-}")'; }
uniq_array() { awk 'NF && !seen[$0]++'; }

aur_exists() {
  local pkg="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$pkg" <<'PY' >/dev/null 2>&1
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
    return $?
  fi
  if command -v git >/dev/null 2>&1; then
    git ls-remote "https://aur.archlinux.org/${pkg}.git" >/dev/null 2>&1
    return $?
  fi
  return 1
}

resolve_package() {
  local pkg="$1"
  local group_members=()
  [[ -n "$pkg" ]] || return 0

  if pacman -Si "$pkg" >/dev/null 2>&1; then
    repo_packages+=("$pkg")
    return 0
  fi
  if pacman -Sgq "$pkg" >/dev/null 2>&1; then
    mapfile -t group_members < <(pacman -Sgq "$pkg")
    repo_packages+=("${group_members[@]}")
    return 0
  fi
  if aur_exists "$pkg"; then
    aur_packages+=("$pkg")
    return 0
  fi
  missing_packages+=("$pkg")
}

select_desktop() {
  case "$desktop" in
    gnome)
      if (( ! additions_only )) && { (( ! is_cachyos )) || (( base_desktop )); }; then
        add_array DESKTOP_GNOME_BASE
      fi
      add_array GNOME_SYSTEM_EXTENSION_PACKAGES
      add_service_array SERVICES_GNOME
      ;;
    hyprland)
      if (( ! additions_only )) && { (( ! is_cachyos )) || (( base_desktop )); }; then
        add_array DESKTOP_HYPRLAND_BASE
      fi
      add_array DESKTOP_HYPRLAND_ADDITIONS
      add_service_array SERVICES_HYPRLAND
      ;;
    kde|plasma)
      if (( ! additions_only )) && { (( ! is_cachyos )) || (( base_desktop )); }; then
        add_array DESKTOP_KDE_BASE
      fi
      add_array DESKTOP_KDE_ADDITIONS
      add_service_array SERVICES_KDE
      ;;
    none|"") echo "No desktop detected/configured; skipping desktop packages" ;;
    *) echo "Unsupported desktop: $desktop" >&2; exit 1 ;;
  esac
}

select_packages() {
  local m="$1"
  case "$m" in
    profile) select_packages base ;;
    system) select_packages system-tools ;;
    overrides) select_packages apps ;;
    full-profile) select_packages full ;;
    bootstrap) add_array BOOTSTRAP ;;
    cli) add_array CLI ;;
    zsh) add_array ZSH ;;
    system-tools)
      add_array SYSTEM_CORE_TOOLS
      add_array SYSTEM_QOL_TOOLS
      add_array SYSTEM_SUPPORT
      if (( is_cachyos )); then
        echo "CachyOS detected: boot support is installer-owned; skipping BOOT_SUPPORT" >&2
      else
        add_array BOOT_SUPPORT
      fi
      ;;
    cpu)
      if (( is_cachyos )); then echo "CachyOS detected: CPU microcode is installer-owned; skipping" >&2; return 0; fi
      case "$cpu" in intel) add_array CPU_INTEL ;; amd) add_array CPU_AMD ;; *) echo "Unknown CPU: $cpu" >&2 ;; esac
      ;;
    gpu)
      if (( is_cachyos )); then echo "CachyOS detected: GPU setup is handled by chwd; skipping" >&2; return 0; fi
      case "$gpu" in amd) add_array GPU_AMD ;; intel) add_array GPU_INTEL ;; nvidia) add_array GPU_NVIDIA ;; *) echo "Unknown GPU: $gpu" >&2 ;; esac
      ;;
    fonts) add_array FONTS_THEMES ;;
    desktop) select_desktop ;;
    apps)
      add_array APPS
      add_array MANUAL_AUR       # shelly (AUR) — installed via the AUR helper
      case "$desktop" in gnome) add_array GNOME_APP_OVERRIDES ;; esac
      ;;
    shell-overrides)
      case "$desktop" in gnome) add_array GNOME_SHELL_OVERRIDES ;; *) echo "No shell overrides defined for desktop=$desktop" >&2 ;; esac
      ;;
    dev-cli) add_array DEV_CLI ;;
    dev)
      if (( force )) || [[ "$role" == *dev* ]]; then
        select_packages dev-cli
        add_array DEV
      else
        echo "dev mode: role='$role' is not dev; skipping (use --force to override)" >&2
      fi
      ;;
    gaming)
      if (( force )) || [[ "$gaming" == "true" || "$role" == *gaming* ]]; then
        add_array GAMING
      else
        echo "gaming mode: gaming='$gaming' role='$role'; skipping (use --force to override)" >&2
      fi
      ;;
    snapshot)
      if (( is_cachyos )); then echo "CachyOS detected: snapshot/bootloader integration is installer-owned; skipping" >&2; return 0; fi
      add_array SNAPSHOT_LIMINE
      ;;
    base|first-install)
      select_packages bootstrap
      select_packages cpu
      select_packages gpu
      select_packages zsh
      select_packages system-tools
      select_packages fonts
      select_packages desktop
      ;;
    full)
      select_packages base
      select_packages cli
      select_packages dev
      select_packages gaming
      ;;
    *) echo "unknown mode: $m" >&2; usage; exit 2 ;;
  esac
}

select_packages "$mode"

mapfile -t selected_packages < <(printf '%s\n' "${selected_packages[@]}" | uniq_array)
mapfile -t services < <(printf '%s\n' "${services[@]}" | uniq_array)

for pkg in "${selected_packages[@]}"; do resolve_package "$pkg"; done

mapfile -t repo_packages < <(printf '%s\n' "${repo_packages[@]}" | uniq_array)
mapfile -t aur_packages < <(printf '%s\n' "${aur_packages[@]}" | uniq_array)
mapfile -t missing_packages < <(printf '%s\n' "${missing_packages[@]}" | uniq_array)

echo "profile: distro=$distro cpu=$cpu gpu=$gpu desktop=$desktop role=$role gaming=$gaming"
echo "mode: $mode"
echo "selected packages: ${selected_packages[*]:-(none)}"
echo "repo packages: ${repo_packages[*]:-(none)}"
echo "aur packages: ${aur_packages[*]:-(none)}"
echo "missing packages: ${missing_packages[*]:-(none)}"
echo "services: ${services[*]:-(none)}"

if ((${#missing_packages[@]})); then
  echo "Missing packages:" >&2
  printf '  %s\n' "${missing_packages[@]}" >&2
  exit 1
fi

(( dry_run )) && exit 0

pacman_args=(-S --needed)
paru_args=(-S --needed)
if (( yes_flag )); then pacman_args+=(--noconfirm); paru_args+=(--noconfirm); fi

if ((${#repo_packages[@]})); then sudo pacman "${pacman_args[@]}" "${repo_packages[@]}"; fi
if ((${#aur_packages[@]})); then
  aur_helper="$("$script_dir/install-aur-helper.sh" "${yes_flag:+--yes}")"
  echo "AUR helper: $aur_helper"
  if [[ "$aur_helper" == "paru" ]]; then
    paru "${paru_args[@]}" "${aur_packages[@]}"
  elif [[ "$aur_helper" == "shelly" ]]; then
    if (( yes_flag )); then
      shelly aur install --no-confirm "${aur_packages[@]}"
    else
      shelly aur install "${aur_packages[@]}"
    fi
  fi
fi

for svc in "${services[@]}"; do
  if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
    sudo systemctl enable "$svc.service" || true
  fi
done
