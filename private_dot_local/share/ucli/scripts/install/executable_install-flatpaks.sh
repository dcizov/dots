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


# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# shellcheck source=/dev/null
source "$real_home/.config/ucli/packages.bash"
# Optional personal overlay (PERSONAL_FLATPAKS), same idea as ~/.config/zsh/local.zsh.
personal_file="$real_home/.config/ucli/packages.local.bash"
if [[ -r "$personal_file" ]]; then
  # shellcheck source=/dev/null
  source "$personal_file"
fi
# shellcheck source=/dev/null
source "$real_home/.config/ucli/scripts/lib/detect.sh"

norm() { tr '[:upper:]' '[:lower:]' <<<"${1:-}" | tr - _; }
desktop="$(norm "${desktop_override:-$(detect_desktop 2>/dev/null || echo none)}")"
role="$(norm "$(detect_role)")"
gaming="$(norm "$(detect_gaming)")"

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
    dev) [[ "$role" == *dev* ]] && add_array DEV_FLATPAKS ;;
    gaming) [[ "$gaming" == true || "$role" == *gaming* ]] && add_array GAMING_FLATPAKS ;;
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
((${#apps[@]})) && flatpak install "$scope" -y flathub "${apps[@]}"
