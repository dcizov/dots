#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: install-flatpaks.sh [--dry-run] [--user|--system] [--desktop=DE] MODE

Modes:
  base          no Flatpaks; kept for first-install compatibility
  apps          personal app Flatpaks + desktop-specific app Flatpaks
  dev           opt-in dev Flatpaks
  gaming        opt-in gaming Flatpaks
  full          apps + dev + gaming(if enabled)

Aliases:
  profile       base
  overrides     apps
  full-profile  full
USAGE
}

dry_run=0
scope="--user"
mode=""
desktop_override=""
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) dry_run=1 ;;
    --user) scope="--user" ;;
    --system) scope="--system" ;;
    --desktop=*) desktop_override="${arg#*=}" ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; usage; exit 2 ;;
    *) mode="$arg" ;;
  esac
done
[[ -n "$mode" ]] || { usage; exit 2; }

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$script_dir/../lib/common.sh"
# shellcheck source=../lib/detect.sh
source "$script_dir/../lib/detect.sh"

real_user="$(ucli_real_user)"
real_home="$(ucli_real_home)"

# Under sudo, --user would install into root's Flatpak store, which no desktop
# session reads: re-run as the invoking user (install-flatpak-gtk-theme.sh does
# the same). --system is the scope that wants root.
if [[ "$scope" == --user && "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
  exec runuser -u "$real_user" -- env HOME="$real_home" "${BASH_SOURCE[0]}" "$@"
fi

# packages.bash and the optional overlay (PERSONAL_FLATPAKS).
ucli_load_packages "$real_home"

desktop="$(ucli_norm "${desktop_override:-$(detect_desktop 2>/dev/null || echo none)}")"
role="$(ucli_norm "$(detect_role)")"
gaming="$(ucli_norm "$(detect_gaming)")"

apps=()
add_array() { local name="$1"; eval 'apps+=("${'"$name"'[@]:-}")'; }

select_apps() {
  case "$1" in
    profile|base|first-install) ;;
    overrides|apps)
      add_array APP_FLATPAKS
      add_array PERSONAL_FLATPAKS
      case "$desktop" in
        gnome) add_array GNOME_FLATPAKS ;;
        kde|plasma) add_array KDE_FLATPAKS ;;
        hyprland) add_array HYPRLAND_FLATPAKS ;;
        none|"") ;;
        *) echo "Unsupported desktop: $desktop" >&2; exit 1 ;;
      esac
      ;;
    # `if`, not `[[ … ]] && add_array`: a false test made the function return 1,
    # and set -e ended the run silently (dev on a non-dev role, and so `full`
    # on any machine that is not both dev and gaming).
    dev) if [[ "$role" == *dev* ]]; then add_array DEV_FLATPAKS; fi ;;
    gaming) if [[ "$gaming" == true || "$role" == *gaming* ]]; then add_array GAMING_FLATPAKS; fi ;;
    full-profile|full) select_apps apps; select_apps dev; select_apps gaming ;;
    *) echo "unknown mode: $1" >&2; usage; exit 2 ;;
  esac
}

select_apps "$mode"
mapfile -t apps < <(printf '%s\n' "${apps[@]}" | awk 'NF && !seen[$0]++')

echo "profile: desktop=$desktop role=$role gaming=$gaming"
echo "mode: $mode"
echo "flatpak scope: $scope"
echo "flatpak apps: ${apps[*]:-(none)}"
(( dry_run )) && exit 0

if ! command -v flatpak >/dev/null 2>&1; then
  sudo pacman -S --needed --noconfirm flatpak
fi
if [[ "$scope" == --user ]]; then
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
else
  sudo flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi
# Not `((${#apps[@]})) && flatpak install …`: on `base` there are no apps, the
# test returns 1, and as the last line of the script that became the script's
# own exit status — a silent `ucli setup-system` failure after the packages were
# already in.
if ((${#apps[@]})); then
  flatpak install "$scope" -y flathub "${apps[@]}"
fi
