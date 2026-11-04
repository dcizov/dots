#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: install-packages.sh [--dry-run] [--yes] [--distro=ID] [--cpu=VENDOR] [--gpu=VENDOR] [--desktop=DE] [--base-desktop] [--additions-only] MODE

Modes:
  base            bootstrap + cpu + gpu + system-tools + fonts + ucli runtime
                  (the shell itself is `shell-tools`; desktop is setup-desktop's job)
  bootstrap       packages needed for chezmoi/ucli bootstrap
  ucli-runtime    ucli's own helpers (gum menus, pipx) — part of base
  cli             opt-in shell cosmetics (starship, eza, bat, zoxide, …)
  shell-tools     the shell tier: zsh + git + curl + starship (what install-shell.sh needs)
  system-tools    system/admin helpers
  cpu             CPU microcode
  gpu             GPU support
  fonts           fonts/themes the shipped configs reference
  fonts-ms        Microsoft core fonts (AUR ttf-ms-fonts)
  desktop         desktop environment packages (+ that desktop's terminal & firefox)
  essentials      firefox + the terminal for the chosen desktop (used by setup-desktop)
  apps            firefox + that desktop's terminal + personal apps and overrides
  media-codecs    gstreamer plugin set + ffmpeg (part of `base`)
  hardware        fprintd / libinput-tools, only if the hardware is present
  dev-cli         opt-in engineering plumbing (jq, ripgrep, tmux, neovim, …)
  dev             opt-in dev-cli + developer packages
  perf            opt-in performance/profiling tooling (perf, bcc, sysprof, …)
  gaming          opt-in gaming packages
  virt            virtual machines: qemu/libvirt/virt-manager (+ `ucli virt` for the service)
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

# Personal picks, if this machine has an overlay (same idea as ~/.config/zsh/
# local.zsh): PERSONAL_PKGS / PERSONAL_DEV / PERSONAL_FLATPAKS /
# PERSONAL_GNOME_EXTENSIONS. Never chezmoi-managed, never required.
personal_file="$real_home/.config/ucli/packages.local.bash"
if [[ -r "$personal_file" ]]; then
  # shellcheck source=/dev/null
  source "$personal_file"
fi

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
# Session services (gdm, sddm) are packages too, and "installed but not enabled"
# is a half-done desktop — so a service array publishes both the unit to enable
# and the package to install. One array, no second list.
add_service_array() {
  local name="$1"
  eval 'services+=("${'"$name"'[@]:-}")'
  eval 'selected_packages+=("${'"$name"'[@]:-}")'
}
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

# The name you type is not always the AUR package name: kwi is packaged as
# kwi-git, which `provides=kwi`. Ask the RPC for providers before calling a package
# missing, and prefer a non-git name when several offer it.
aur_provides() {
  local pkg="$1"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$pkg" <<'PY' 2>/dev/null || true
import json, sys, urllib.parse, urllib.request
pkg = sys.argv[1]
url = "https://aur.archlinux.org/rpc/v5/search?" + urllib.parse.urlencode({"arg[]": pkg, "by": "provides"})
with urllib.request.urlopen(url, timeout=15) as response:
    data = json.load(response)
providers = [r["Name"] for r in data.get("results", []) if pkg in (r.get("Provides") or [])]
providers.sort(key=lambda name: (name.endswith("-git"), name))
if providers:
    print(providers[0])
PY
}

resolve_package() {
  local pkg="$1"
  local group_members=()
  local aur_name=""
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
  # Exact AUR name first (the common case, one RPC query), providers second.
  if aur_exists "$pkg"; then
    aur_packages+=("$pkg")
    return 0
  fi
  if aur_name="$(aur_provides "$pkg")" && [[ -n "$aur_name" ]]; then
    aur_packages+=("$aur_name")
    echo "note: $pkg is provided by the AUR package $aur_name" >&2
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

  select_essentials
}

# The browser is desktop-agnostic; the terminal follows the desktop (GNOME and
# Hyprland get ghostty, KDE gets kwi — see packages.bash for why). On a machine
# with no desktop at all neither is added: a TTY-only box gets ucli and nothing
# else, and ~/.config/<terminal> is not deployed for a program that is not there
# (.chezmoiignore asks lookPath).
select_essentials() {
  case "$desktop" in
    gnome)
      add_array DESKTOP_TERMINAL_GNOME
      # The repo-packaged extensions (and gnome-shell-extensions, which carries
      # user-theme) belong here: setup-desktop.sh installs the DE itself and
      # never calls `desktop` mode, so anything listed only there never lands.
      add_array GNOME_SYSTEM_EXTENSION_PACKAGES
      ;;
    hyprland)  add_array DESKTOP_TERMINAL_HYPRLAND ;;
    kde|plasma) add_array DESKTOP_TERMINAL_KDE ;;
    none|"")   return 0 ;;
  esac
  add_array DESKTOP_BROWSER
}

select_packages() {
  local m="$1"
  case "$m" in
    profile) select_packages base ;;
    system) select_packages system-tools ;;
    overrides) select_packages apps ;;
    full-profile) select_packages full ;;
    bootstrap) add_array BOOTSTRAP ;;
    ucli-runtime|runtime) add_array UCLI_RUNTIME ;;
    cli) add_array CLI ;;
    shell-tools|shell-deps) add_array SHELL_TOOLS ;;
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
    fonts-ms) add_array FONTS_MS ;;
    essentials) select_essentials ;;
    desktop) select_desktop ;;
    apps)
      select_essentials              # the desktop's terminal, idempotent with desktop mode
      add_array DESKTOP_BROWSER      # firefox is desktop-agnostic: `ucli apps` gets a
                                     # browser even when the desktop cannot be detected
      add_array APPS
      add_array MANUAL_AUR       # shelly (AUR) — installed via the AUR helper
      add_array PERSONAL_PKGS    # packages.local.bash, empty when not set
      case "$desktop" in gnome) add_array GNOME_APP_OVERRIDES ;; esac
      ;;
    media-codecs) add_array SYSTEM_MEDIA_CODECS ;;
    hardware)
      # Only what this machine actually has: a fingerprint reader needs fprintd,
      # a touchpad or trackpoint makes libinput's CLI useful. Both are skipped
      # silently on hardware that does not need them.
      if [[ "$(detect_fingerprint 2>/dev/null || echo no)" == yes ]]; then
        echo "hardware: fingerprint reader found, adding fprintd" >&2
        add_array HARDWARE_FINGERPRINT
      fi
      if [[ "$(detect_touchpad 2>/dev/null || echo no)" == yes ]]; then
        echo "hardware: touchpad/trackpoint found, adding libinput-tools" >&2
        add_array HARDWARE_TOUCHPAD
      fi
      ;;
    dev-cli) add_array DEV_CLI ;;
    perf) add_array DEV_PERF ;;
    dev)
      if (( force )) || [[ "$role" == *dev* ]]; then
        select_packages dev-cli
        add_array DEV
        add_array PERSONAL_DEV     # packages.local.bash, empty when not set
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
    virt) add_array VIRT ;;
    snapshot)
      if (( is_cachyos )); then echo "CachyOS detected: snapshot/bootloader integration is installer-owned; skipping" >&2; return 0; fi
      add_array SNAPSHOT_LIMINE
      ;;
    base|first-install)
      # No desktop here: setup-desktop.sh owns that step (replacement matrix,
      # firefox + terminal, GNOME extensions, snapshot). `ucli setup-system` chains
      # into it; `install-packages.sh desktop` remains for manual use.
      select_packages ucli-runtime
      select_packages bootstrap
      select_packages cpu
      select_packages gpu
      select_packages system-tools
      select_packages media-codecs
      select_packages hardware
      select_packages fonts
      ;;
    full)
      select_packages base
      select_packages desktop
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
    # --needed skips already-installed AUR packages (idempotent re-runs)
    # --no-confirm makes shelly non-interactive (no prompts)
    shelly install aur "${aur_packages[@]}" --needed --no-confirm
  fi
fi

for svc in "${services[@]}"; do
  if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
    sudo systemctl enable "$svc.service" || true
  fi
done
