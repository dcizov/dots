#!/usr/bin/env bash
# Install Betterfox user.js into every Firefox profile.
#
# Copies the vendored user.js (Betterfox v154 + user overrides) into each profile,
# so the config applies on the next Firefox restart. Profile locations differ by
# Firefox version — ~/.config/mozilla/firefox on 147+, ~/.mozilla/firefox before
# that — and lib/firefox.sh resolves both.
#
# Works on all desktops (gnome, hyprland, kde) — Firefox is desktop-agnostic.
#
# Source: https://github.com/yokoffing/Betterfox
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# When run via sudo, use the invoking user's home
real_user="${SUDO_USER:-$USER}"
real_home="$(getent passwd "$real_user" | cut -d: -f6)"

if ! command -v firefox >/dev/null 2>&1; then
  echo "firefox not installed; skipping Betterfox" >&2
  exit 0
fi

# Where Firefox keeps its profiles (147+ XDG, legacy, flatpak) lives in one place.
fx_lib="$real_home/.config/ucli/scripts/lib/firefox.sh"
if [[ ! -r "$fx_lib" ]]; then
  echo "error: $fx_lib missing; run 'ucli chezmoi-apply' to deploy the ucli scripts" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$fx_lib"

PROFILE_DIR="$(fx_profile_root "$real_home")"
SOURCE_USER_JS="$(fx_config_dir "$real_home")/user.js"

if [[ ! -d "$PROFILE_DIR" ]]; then
  echo "no Firefox profile found ($(fx_short_root "$PROFILE_DIR" "$real_home")); skipping Betterfox" >&2
  echo "  launch Firefox once to create a profile, then re-run: ucli apps" >&2
  exit 0
fi

# user.js is chezmoi-managed and only deployed once firefox exists
# (.chezmoiignore asks lookPath), so a machine that just installed firefox in this
# very run has the binary but not the file. Deploy that one target first.
if [[ ! -f "$SOURCE_USER_JS" ]] && command -v chezmoi >/dev/null 2>&1; then
  echo "firefox config not deployed yet; running: chezmoi apply -- $SOURCE_USER_JS"
  chezmoi apply -- "$SOURCE_USER_JS" >/dev/null 2>&1 || true
fi

if [[ ! -f "$SOURCE_USER_JS" ]]; then
  echo "Betterfox user.js not found at $SOURCE_USER_JS; skipping" >&2
  echo "  deploy it first: ucli chezmoi-apply" >&2
  exit 0
fi

# Versioned gate: the token is the content hash of the source user.js, so the
# copy only happens when Betterfox (or one of your overrides) actually changed.
# --force re-copies into every profile.
# shellcheck source=/dev/null
if [[ -r "$real_home/.config/ucli/scripts/lib/version-script.sh" ]]; then
  source "$real_home/.config/ucli/scripts/lib/version-script.sh"
  force=0
  [[ "${1:-}" == "--force" ]] && force=1
  betterfox_version="$(vs_hash "$SOURCE_USER_JS")"
  if (( ! force )) && ! vs_check firefox-betterfox user "$betterfox_version"; then
    echo "Betterfox user.js unchanged since the last run (${betterfox_version}); skipping."
    echo "    re-run with --force to copy it into every profile again"
    exit 0
  fi
fi

# Every profile Firefox knows about gets the same user.js.
echo "Installing Betterfox user.js into Firefox profiles ($(fx_short_root "$PROFILE_DIR" "$real_home")) ..."

while IFS= read -r prof_dir; do
  [[ -n "$prof_dir" ]] || continue
  cp -f "$SOURCE_USER_JS" "$prof_dir/user.js"
  echo "  installed to $(fx_short_root "$prof_dir" "$real_home")/user.js"
done < <(fx_profile_dirs "$PROFILE_DIR")

[[ -n "${betterfox_version:-}" ]] && vs_commit firefox-betterfox user "$betterfox_version"
echo "Betterfox user.js installed. Restart Firefox to apply."