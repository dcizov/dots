# Firefox locations — one place, four readers.
# shellcheck shell=bash
#
# Firefox changed its Linux layout in 147 (August 2026): profiles moved to the
# XDG base directory spec, so a *new* install keeps them in
#
#   ~/.config/mozilla/firefox/<profile>/     (FF 147+, XDG)
#   ~/.cache/mozilla/firefox/                (cache)
#
# and an install that already had a profile keeps the pre-147 layout:
#
#   ~/.mozilla/firefox/<profile>/
#
# Firefox only migrates on a fresh profile root, so both spellings are live on
# Arch and CachyOS today (archinstall + firefox from extra gives the XDG one, an
# upgraded machine keeps ~/.mozilla). MOZ_LEGACY_HOME=1 pins the old layout. A
# flatpak install sandboxes both inside ~/.var/app/org.mozilla.firefox/.
#
# Everything here therefore resolves the *root*, then reads profiles.ini for the
# profile directories — never guess a profile name, and never write into the root
# itself: user.js belongs next to prefs.js inside a profile.
#
# The repo's own sources (user.js + the two extension lists) are NOT a Firefox
# path. They live in ~/.config/ucli/firefox/ and are copied into every profile,
# which keeps `ucli uninstall` from deleting somebody's profile directory.

# fx_profile_root [home] — the profile root Firefox actually uses on this machine.
# Prints a path even when nothing exists yet (the 147+ default), so callers can
# test it with [[ -d ]].
fx_profile_root() {
  local home="${1:-$HOME}"
  local xdg="$home/.config/mozilla/firefox"
  local legacy="$home/.mozilla/firefox"
  local flatpak_xdg="$home/.var/app/org.mozilla.firefox/config/mozilla/firefox"
  local flatpak_legacy="$home/.var/app/org.mozilla.firefox/.mozilla/firefox"
  local dir

  # MOZ_LEGACY_HOME forces the pre-147 layout.
  if [[ -n "${MOZ_LEGACY_HOME:-}" && -d "$legacy" ]]; then
    printf '%s\n' "$legacy"
    return 0
  fi

  # profiles.ini is what Firefox reads first, and an existing legacy root wins —
  # that is exactly what Firefox does, so we agree with it instead of guessing.
  for dir in "$legacy" "$xdg" "$flatpak_xdg" "$flatpak_legacy"; do
    if [[ -f "$dir/profiles.ini" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done

  # No profiles.ini yet. Report whichever root exists (first launch will fill it),
  # otherwise the 147+ default, so `firefox` can be configured before it is run.
  for dir in "$xdg" "$legacy" "$flatpak_xdg" "$flatpak_legacy"; do
    if [[ -d "$dir" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done

  printf '%s\n' "$xdg"
}

# fx_profile_dirs [root] — one directory per profile, from profiles.ini.
# Handles IsRelative (the default), absolute Path=, CRLF files, and skips sections
# without a Path (the [Install…] blocks), which is why this is not a `grep Path=`.
fx_profile_dirs() {
  local root="${1:-$(fx_profile_root)}"
  local ini="$root/profiles.ini"
  [[ -r "$ini" ]] || return 0

  local line path is_rel=1 dir
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    case "$line" in
      \[*)
        is_rel=1
        ;;
      IsRelative=*)
        is_rel="${line#IsRelative=}"
        ;;
      Path=*)
        path="${line#Path=}"
        if [[ "$is_rel" == "0" || "$path" == /* ]]; then
          dir="$path"
        else
          dir="$root/$path"
        fi
        [[ -d "$dir" ]] && printf '%s\n' "$dir"
        ;;
    esac
  done <"$ini"
}

# fx_config_dir [home] — where this repo keeps user.js and the extension lists.
fx_config_dir() {
  local home="${1:-$HOME}"
  printf '%s\n' "$home/.config/ucli/firefox"
}

# fx_short_root <root> [home] — `~`-relative spelling for user-facing output.
fx_short_root() {
  local root="$1"
  local home="${2:-$HOME}"
  printf '%s\n' "${root#"$home"/}"
}
