#!/usr/bin/env bash
# Personal apps and desktop overrides (this is `ucli apps`).
#
#   packages   APPS + this desktop's app overrides, MANUAL_AUR (shelly), firefox
#              and the desktop's terminal (idempotent with setup-desktop.sh)
#   flatpaks   APP_FLATPAKS + this desktop's flatpaks
#   firefox    profile + Betterfox + GNOME theme via install-firefox-profile.sh
#              (shared with setup-desktop.sh, so normally already done), then the
#              extension lists (repo + personal)
#   gnome      the "personal" GNOME extension set, on GNOME only
#
# Usage: install-overrides.sh [--force]
#   --force re-runs the versioned steps (Betterfox copy, override extension set)
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

force_args=()
for arg in "$@"; do
  case "$arg" in
    --force) force_args=(--force) ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# shellcheck source=/dev/null
source "$real_home/.local/share/ucli/scripts/lib/detect.sh"

# Detect desktop for gnome-only blocks (firefox-gnome-theme, gnome extensions)
desktop="$(detect_desktop 2>/dev/null || echo none)"

"$script_dir/install-packages.sh" apps
"$script_dir/install-flatpaks.sh" apps

fx_lib="$real_home/.local/share/ucli/scripts/lib/firefox.sh"
if [[ -r "$fx_lib" ]]; then
  # shellcheck source=/dev/null
  source "$fx_lib"
else
  echo "warning: $fx_lib missing; Firefox handling is skipped (run: ucli chezmoi-apply)" >&2
  exit 1
fi

# Everything that makes Firefox a configured browser — profile creation, Betterfox
# user.js, and on GNOME the GNOME theme — lives with the browser, not here. The
# desktop step already ran it; this call keeps `ucli apps` self-sufficient when
# firefox is installed from this path, and is a no-op otherwise.
"$script_dir/install-firefox-profile.sh" ${force_args[@]+"${force_args[@]}"} || true

# Extension lists stay in apps on purpose: which add-ons you want (and which dev
# add-ons, via ucli devmode) is personal, the config above is not. The repo file
# holds the opinionated ones; personal-extensions.txt is yours and optional.
#
# Both lists end up as Firefox *policies* (/etc/firefox/policies/policies.json),
# not as XPI files inside a profile: the policy is what makes them installed and
# enabled without a first launch, and it is the mechanism Mozilla documents for
# unattended installs. See the script's header for why the alternatives lost.
fx_dir="$(fx_config_dir "$real_home")"
rc=0
if [[ -x "$script_dir/install-firefox-policies.sh" ]]; then
  sudo "$script_dir/install-firefox-policies.sh" || rc=$?
  if ((${rc:-0} != 0)); then
    echo "warning: Firefox extensions were not configured (exit $rc);" >&2
    echo "         re-run: sudo ucli firefox-policies" >&2
  fi
fi

if [[ "$desktop" == "gnome" ]]; then
  "$script_dir/install-gnome-extension-set.sh" personal ${force_args[@]+"${force_args[@]}"} || true
fi
