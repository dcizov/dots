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
# shellcheck source=../lib/common.sh
source "$script_dir/../lib/common.sh"
# Where Firefox keeps its profiles (147+ XDG, legacy, flatpak) lives in one place.
# shellcheck source=../lib/firefox.sh
source "$script_dir/../lib/firefox.sh"
# shellcheck source=../lib/version-script.sh
source "$script_dir/../lib/version-script.sh"

force=0
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    -h|--help) ucli_script_help; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# Under sudo: the invoking user's home and profiles, not root's.
real_home="$(ucli_real_home)"

if ! command -v firefox >/dev/null 2>&1; then
  echo "firefox not installed; skipping Betterfox" >&2
  exit 0
fi

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
betterfox_version="$(vs_hash "$SOURCE_USER_JS")"
if (( ! force )) && ! vs_check firefox-betterfox user "$betterfox_version"; then
  echo "Betterfox user.js unchanged since the last run (${betterfox_version}); skipping."
  echo "    re-run with --force to copy it into every profile again"
  exit 0
fi

# Every profile Firefox knows about gets the same user.js.
echo "Installing Betterfox user.js into Firefox profiles ($(fx_short_root "$PROFILE_DIR" "$real_home")) ..."

copied=0
while IFS= read -r prof_dir; do
  [[ -n "$prof_dir" ]] || continue
  cp -f "$SOURCE_USER_JS" "$prof_dir/user.js"
  echo "  installed to $(fx_short_root "$prof_dir" "$real_home")/user.js"
  copied=$((copied + 1))
done < <(fx_profile_dirs "$PROFILE_DIR")

# Commit the gate only once a profile got the file: a root with no profile yet
# (Firefox never launched) used to commit it anyway, and the profile created
# later was then skipped as "unchanged" on every run.
if (( copied == 0 )); then
  echo "no profile in profiles.ini yet; launch Firefox once, then re-run: ucli apps" >&2
  exit 0
fi
vs_commit firefox-betterfox user "$betterfox_version"
echo "Betterfox user.js installed. Restart Firefox to apply."