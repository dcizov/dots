#!/usr/bin/env bash
# install-firefox-gnome-theme.sh: clone the theme and run its own install.sh
# against the profile root, reporting a failed install instead of claiming
# success. git is a stub that "clones" a fake install.sh.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

theme() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-firefox-gnome-theme.sh "$@" ); }

ROOT() { printf '%s' "$HOME/.config/mozilla/firefox"; }

# world [install-exit] — firefox, a profile root, and a git that clones a theme
# whose install.sh records its arguments and exits with install-exit.
world() {
  stub firefox
  mkdir -p "$(ROOT)"
  stub git "dest=\${@: -1}; mkdir -p \"\$dest/scripts\"
    printf '#!/usr/bin/env bash\\necho \"theme-install \$*\" >>\"\$T_CALLS\"\\nexit ${1:-0}\\n' >\"\$dest/scripts/install.sh\""
}

test_the_theme_installer_runs_against_the_profile_root() {
  world
  t_run theme
  assert_status 0
  assert_called "git clone --depth=1 https://github.com/rafaelmardojai/firefox-gnome-theme.git"
  assert_called "theme-install -f $(ROOT)"
  assert_contains "$T_OUT" "firefox-gnome-theme installed."
}

test_a_failed_install_is_reported_not_celebrated() {
  world 1
  t_run theme
  assert_status 1
  assert_contains "$T_OUT" "install script failed"
  assert_not_contains "$T_OUT" "firefox-gnome-theme installed."
}

test_a_failed_clone_is_a_warning() {
  world
  stub git 'exit 128'
  t_run theme
  assert_status 0
  assert_contains "$T_OUT" "could not clone firefox-gnome-theme repo"
}

test_the_callers_TMPDIR_is_left_alone() {
  world
  export TMPDIR="$T_ROOT/tmp"
  mkdir -p "$TMPDIR"
  stub git "[[ \$TMPDIR == '$T_ROOT/tmp' ]] || echo \"TMPDIR changed to \$TMPDIR\" >>\"\$T_CALLS\"; exit 128"
  t_run theme
  assert_not_called "TMPDIR changed"
}

test_skips_without_firefox_or_a_profile_root() {
  t_minimal_path
  t_run theme
  assert_contains "$T_OUT" "firefox not installed; skipping"
  stub firefox
  t_run theme
  assert_status 0
  assert_contains "$T_OUT" "no Firefox profile found (~/.config/mozilla/firefox)"
  assert_not_called "git"
}

test_arguments() {
  t_run theme --bogus
  assert_status 2
}

t_main
