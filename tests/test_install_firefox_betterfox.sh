#!/usr/bin/env bash
# install-firefox-betterfox.sh: copy ~/.config/ucli/firefox/user.js into every
# profile, gated on its content hash, and never mark a run done that reached
# no profile.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

betterfox() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-firefox-betterfox.sh "$@" ); }

ROOT() { printf '%s' "$HOME/.config/mozilla/firefox"; }

# firefox_with <profile…> — firefox on PATH, user.js deployed, and a profile
# root whose profiles.ini lists the given profiles.
firefox_with() {
  stub firefox
  mkdir -p "$HOME/.config/ucli/firefox" "$(ROOT)"
  echo 'user_pref("browser.startup.page", 3);' >"$HOME/.config/ucli/firefox/user.js"
  : >"$(ROOT)/profiles.ini"
  local p i=0
  for p in "$@"; do
    mkdir -p "$(ROOT)/$p"
    printf '[Profile%d]\nIsRelative=1\nPath=%s\n' "$i" "$p" >>"$(ROOT)/profiles.ini"
    i=$((i + 1))
  done
}

test_user_js_goes_into_every_profile() {
  firefox_with a.default b.work
  t_run betterfox
  assert_status 0
  assert_eq "$(cat "$HOME/.config/ucli/firefox/user.js")" "$(cat "$(ROOT)/a.default/user.js")"
  assert_file "$(ROOT)/b.work/user.js"
  assert_contains "$T_OUT" "installed to ~/.config/mozilla/firefox/b.work/user.js"
}

test_an_unchanged_user_js_is_not_copied_again_unless_forced() {
  firefox_with a.default
  betterfox >/dev/null 2>&1
  rm "$(ROOT)/a.default/user.js"
  t_run betterfox
  assert_contains "$T_OUT" "unchanged since the last run"
  assert_no_file "$(ROOT)/a.default/user.js"
  t_run betterfox --force
  assert_file "$(ROOT)/a.default/user.js"
  echo '// changed' >>"$HOME/.config/ucli/firefox/user.js"
  rm "$(ROOT)/a.default/user.js"
  t_run betterfox
  assert_file "$(ROOT)/a.default/user.js"
}

test_a_root_without_profiles_does_not_close_the_gate() {
  firefox_with
  t_run betterfox
  assert_status 0
  assert_contains "$T_OUT" "no profile in profiles.ini yet"
  # Firefox launches and creates its profile: the next run must still copy.
  mkdir -p "$(ROOT)/new.default"
  printf '[Profile0]\nIsRelative=1\nPath=new.default\n' >"$(ROOT)/profiles.ini"
  t_run betterfox
  assert_file "$(ROOT)/new.default/user.js"
}

test_skips_without_firefox_profile_root_or_user_js() {
  t_minimal_path
  t_run betterfox
  assert_contains "$T_OUT" "firefox not installed; skipping Betterfox"
  stub firefox
  t_run betterfox
  assert_contains "$T_OUT" "no Firefox profile found (~/.config/mozilla/firefox)"
  mkdir -p "$(ROOT)"
  t_run betterfox
  assert_status 0
  assert_contains "$T_OUT" "Betterfox user.js not found"
}

test_a_missing_user_js_is_deployed_with_chezmoi_first() {
  firefox_with a.default
  rm "$HOME/.config/ucli/firefox/user.js"
  stub chezmoi 'echo "// from chezmoi" >"$3"'
  t_run betterfox
  assert_called "chezmoi apply -- $HOME/.config/ucli/firefox/user.js"
  assert_eq "// from chezmoi" "$(cat "$(ROOT)/a.default/user.js")"
}

test_arguments() {
  t_run betterfox --bogus
  assert_status 2
}

t_main
