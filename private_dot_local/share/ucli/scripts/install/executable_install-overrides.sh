#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, $HOME is root's home; use the invoking user's home instead.
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

# shellcheck source=/dev/null
source "$real_home/.config/ucli/scripts/lib/detect.sh"

# Detect desktop for gnome-only blocks (firefox-gnome-theme, gnome extensions)
desktop="$(detect_desktop 2>/dev/null || echo none)"

"$script_dir/install-packages.sh" apps
"$script_dir/install-flatpaks.sh" apps

# Firefox writes user.js and extensions into a *profile*, and a profile only
# exists after Firefox has started once. On a fresh machine that used to mean
# both steps below silently skipped themselves and you ended up with a stock
# browser. Create the profile headlessly instead of asking the user to remember.
firefox_profiles_ini() {
  local candidate
  for candidate in "$real_home/.config/mozilla/firefox/profiles.ini" \
                   "$real_home/.mozilla/firefox/profiles.ini"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

firefox_headless() {
  # --screenshot exits on its own once it has written the file, which is the
  # cheapest way to make Firefox create its profile and quit. Older builds may
  # not exit, so everything is wrapped in timeout and failures are ignored.
  local shot
  shot="$(mktemp -u "${TMPDIR:-/tmp}/ucli-firefox-XXXXXX.png")"
  if [[ "$EUID" -eq 0 ]]; then
    runuser -u "$real_user" -- timeout 40 firefox --headless --screenshot "$shot" about:blank \
      >/dev/null 2>&1 || true
  else
    timeout 40 firefox --headless --screenshot "$shot" about:blank >/dev/null 2>&1 || true
  fi
  rm -f "$shot"
}

ensure_firefox_profile() {
  firefox_profiles_ini >/dev/null && return 0
  if ! command -v firefox >/dev/null 2>&1; then
    echo "warning: firefox is not installed; skipping profile setup" >&2
    return 0
  fi
  echo "Firefox has no profile yet; creating one headlessly ..."
  firefox_headless
  if firefox_profiles_ini >/dev/null; then
    echo "Firefox profile created."
  else
    echo "warning: could not create a Firefox profile; launch Firefox once, then re-run 'ucli apps'" >&2
  fi
}

ensure_firefox_profile

# Firefox Betterfox user.js — applies on all desktops (Firefox is desktop-agnostic).
# The profile now exists by construction: ensure_firefox_profile above.
"$script_dir/install-firefox-betterfox.sh" || true

# Firefox extensions (regular) — same profile, now guaranteed above
"$script_dir/install-firefox-extensions.sh" "$real_home/.config/firefox/extensions.txt" || true

if [[ "$desktop" == "gnome" ]]; then
  "$script_dir/install-gnome-extension-set.sh" overrides || true
  # Firefox GNOME theme — only makes sense on GNOME desktop (same profile)
  "$script_dir/install-firefox-gnome-theme.sh" || true
fi