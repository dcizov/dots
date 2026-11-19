#!/usr/bin/env bash
# install-firefox-profile.sh: create a profile headlessly when there is none,
# then hand over to the Betterfox copy and, on GNOME only, the GNOME theme.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

profile() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-firefox-profile.sh "$@" ); }

ROOT() { printf '%s' "$HOME/.config/mozilla/firefox"; }

# world [creates 0|1] — a firefox whose headless screenshot run creates a
# profile (like the real first start) unless told not to, and the deployed
# script with recording fakes for its two siblings.
world() {
  stub firefox "[[ ${1:-1} == 1 ]] || exit 0
    mkdir -p \"\$HOME/.config/mozilla/firefox/abc.default-release\"
    printf '[Profile0]\\nIsRelative=1\\nPath=abc.default-release\\n' >\"\$HOME/.config/mozilla/firefox/profiles.ini\""
  stub timeout 'shift; "$@"'
  S="$(t_deployed install/install-firefox-profile)"
  t_fake_script "${S%/*}/install-firefox-betterfox.sh"
  t_fake_script "${S%/*}/install-firefox-gnome-theme.sh"
}

test_a_missing_profile_is_created_headlessly() {
  world
  t_run bash "$S"
  assert_status 0
  assert_called "firefox --headless --screenshot"
  assert_contains "$T_OUT" "Firefox profile created."
  assert_file "$(ROOT)/profiles.ini"
  assert_called "install-firefox-betterfox.sh"
}

test_an_existing_profile_is_not_recreated() {
  world
  mkdir -p "$(ROOT)"; : >"$(ROOT)/profiles.ini"
  t_run bash "$S" --force
  assert_not_called "firefox --headless"
  assert_called "install-firefox-betterfox.sh --force"
}

test_a_firefox_that_creates_nothing_is_reported() {
  world 0
  t_run bash "$S"
  assert_status 0
  assert_contains "$T_OUT" "could not create a Firefox profile"
}

test_the_gnome_theme_only_on_gnome() {
  world
  XDG_CURRENT_DESKTOP=GNOME t_run bash "$S"
  assert_called "install-firefox-gnome-theme.sh"
  : >"$T_CALLS"
  XDG_CURRENT_DESKTOP=KDE t_run bash "$S"
  assert_not_called "install-firefox-gnome-theme.sh"
  assert_contains "$T_OUT" "skipping firefox-gnome-theme"
}

test_without_firefox_nothing_happens() {
  t_minimal_path
  t_run profile
  assert_status 0
  assert_contains "$T_OUT" "firefox not installed; skipping"
}

test_arguments() {
  t_run profile --bogus
  assert_status 2
  t_run profile --help
  assert_contains "$T_OUT" "Usage: install-firefox-profile.sh [--force]"
}

t_main
