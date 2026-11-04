#!/usr/bin/env bash
# Configure Firefox the moment it is installed — no `ucli apps` step needed.
#
#   1. create a profile if there is none (headless --screenshot, then quit)
#   2. copy the Betterfox user.js into every profile (versioned gate, --force)
#   3. on GNOME, install firefox-gnome-theme into that profile
#
# Firefox's config belongs to "firefox is installed", not to "personal apps":
# setup-desktop.sh runs this after the dotfiles deploy and before the "<DE> Setup"
# snapshot, so the browser is already configured in the restore point.
# install-overrides.sh (ucli apps) runs it too, because apps can install firefox
# on its own; both paths are idempotent and share this one implementation.
#
# The Firefox extension list stays in `ucli apps`: which add-ons you want
# (extensions.txt, dev-extensions.txt) is personal, the config is not.
#
# Usage: install-firefox-profile.sh [--force]
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

force_args=()
for arg in "$@"; do
  case "$arg" in
    --force) force_args=(--force) ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# When run via sudo, use the invoking user's home — a profile in /root is useless.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

if ! command -v firefox >/dev/null 2>&1; then
  echo "firefox not installed; skipping Firefox profile setup" >&2
  exit 0
fi

# Profile locations (147+ XDG, legacy ~/.mozilla, flatpak) live in one place.
fx_lib="$real_home/.local/share/ucli/scripts/lib/firefox.sh"
if [[ ! -r "$fx_lib" ]]; then
  echo "error: $fx_lib missing; run 'ucli chezmoi-apply' to deploy the ucli scripts" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$fx_lib"

firefox_profiles_ini() {
  local root
  root="$(fx_profile_root "$real_home")"
  [[ -f "$root/profiles.ini" ]] || return 1
  printf '%s\n' "$root/profiles.ini"
}

firefox_headless() {
  # --screenshot exits on its own once it has written the file, which is the
  # cheapest way to make Firefox create its profile and quit. Older builds may
  # not exit, so everything is wrapped in timeout and failures are ignored.
  local shot_dir shot
  # mktemp -u only *names* a file; a private directory cannot be raced.
  shot_dir="$(mktemp -d "${TMPDIR:-/tmp}/ucli-firefox-XXXXXX")"
  shot="$shot_dir/shot.png"
  if [[ "$EUID" -eq 0 ]]; then
    runuser -u "$real_user" -- timeout 40 firefox --headless --screenshot "$shot" about:blank \
      >/dev/null 2>&1 || true
  else
    timeout 40 firefox --headless --screenshot "$shot" about:blank >/dev/null 2>&1 || true
  fi
  rm -rf "$shot_dir"
}

# Firefox writes user.js and extensions into a *profile*, and a profile only
# exists after Firefox has started once. On a fresh machine that used to mean
# every later step silently skipped itself and you ended up with a stock browser.
ensure_firefox_profile() {
  firefox_profiles_ini >/dev/null && return 0
  echo "Firefox has no profile yet; creating one headlessly ..."
  firefox_headless
  if firefox_profiles_ini >/dev/null; then
    echo "Firefox profile created."
  else
    echo "warning: could not create a Firefox profile; launch Firefox once, then re-run 'ucli setup-desktop'" >&2
  fi
}

ensure_firefox_profile

# Betterfox user.js — Firefox is desktop-agnostic, so this runs everywhere.
# The gate is the hash of ~/.config/ucli/firefox/user.js; --force re-copies.
"$script_dir/install-firefox-betterfox.sh" ${force_args[@]+"${force_args[@]}"} || true

# firefox-gnome-theme — only makes sense on GNOME, where it also needs the
# user-theme extension to apply.
desktop="none"
detect_lib="$real_home/.local/share/ucli/scripts/lib/detect.sh"
if [[ -r "$detect_lib" ]]; then
  desktop="$( (
    # shellcheck source=/dev/null
    source "$detect_lib"
    detect_desktop
  ) 2>/dev/null || echo none )"
fi

case "$desktop" in
  gnome|gnome-*)
    "$script_dir/install-firefox-gnome-theme.sh" || true
    ;;
  *)
    echo "desktop is ${desktop:-unknown}; skipping firefox-gnome-theme"
    ;;
esac

echo "Firefox profile configured."
