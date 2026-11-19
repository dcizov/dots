#!/usr/bin/env bash
# lib/firefox.sh: which profile root Firefox uses (legacy wins when it has a
# profiles.ini, 147+ XDG otherwise, flatpak last), the profile directories
# profiles.ini lists, and the display spelling.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

fx() { source ../private_dot_local/share/ucli/scripts/lib/firefox.sh; }

ini() { mkdir -p "$1"; printf '%s\n' "${@:2}" >"$1/profiles.ini"; }

test_a_fresh_machine_gets_the_xdg_default() {
  fx
  assert_eq "$HOME/.config/mozilla/firefox" "$(fx_profile_root "$HOME")"
}

test_an_existing_legacy_profile_root_wins() {
  fx
  ini "$HOME/.mozilla/firefox" "[Profile0]"
  mkdir -p "$HOME/.config/mozilla/firefox"
  assert_eq "$HOME/.mozilla/firefox" "$(fx_profile_root "$HOME")"
}

test_xdg_with_profiles_beats_a_bare_legacy_dir() {
  fx
  mkdir -p "$HOME/.mozilla/firefox"
  ini "$HOME/.config/mozilla/firefox" "[Profile0]"
  assert_eq "$HOME/.config/mozilla/firefox" "$(fx_profile_root "$HOME")"
}

test_moz_legacy_home_pins_the_old_layout() {
  fx
  mkdir -p "$HOME/.mozilla/firefox"
  ini "$HOME/.config/mozilla/firefox" "[Profile0]"
  MOZ_LEGACY_HOME=1
  assert_eq "$HOME/.mozilla/firefox" "$(fx_profile_root "$HOME")"
}

test_flatpak_roots_are_found() {
  fx
  ini "$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox" "[Profile0]"
  assert_eq "$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox" "$(fx_profile_root "$HOME")"
}

test_profile_dirs_follow_profiles_ini() {
  fx
  local r="$HOME/.config/mozilla/firefox" abs="$T_ROOT/elsewhere/abs.profile"
  mkdir -p "$r/rel.default" "$abs"
  ini "$r" "[Install4F96D1932A9F858E]" "Default=rel.default" "" \
    "[Profile0]" "Name=default" "IsRelative=1" $'Path=rel.default\r' "" \
    "[Profile1]" "Name=abs" "IsRelative=0" "Path=$abs" "" \
    "[Profile2]" "Name=gone" "IsRelative=1" "Path=deleted.profile"
  assert_eq "$r/rel.default"$'\n'"$abs" "$(fx_profile_dirs "$r")"
}

test_no_profiles_ini_means_no_dirs() {
  fx
  assert_eq "" "$(fx_profile_dirs "$T_ROOT/none")"
}

test_short_root_spells_paths_under_home_with_a_tilde() {
  fx
  # shellcheck disable=SC2088  # the literal ~ is the expected display text
  assert_eq "~/.mozilla/firefox" "$(fx_short_root "$HOME/.mozilla/firefox" "$HOME")"
  assert_eq "/opt/firefox" "$(fx_short_root /opt/firefox "$HOME")"
  assert_eq "$HOME/.config/ucli/firefox" "$(fx_config_dir "$HOME")"
}

t_main
