#!/usr/bin/env bash
# provision-dev.sh runs as root inside the Debian dev box, so a full run needs
# a container. What is testable here: the root gate, and the helpers the run is
# built on (sourced with DEVBOX_HELPERS_ONLY=1, which stops before any change).
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

helpers() {
  DEVBOX_HELPERS_ONLY=1
  source ../private_dot_config/distrobox/executable_provision-dev.sh
  set +e   # the script's own set -e is for the script, not for the assertions
}

test_dur_formats_seconds_and_minutes() {
  helpers
  assert_eq "0s" "$(dur 0)"
  assert_eq "42s" "$(dur 42)"
  assert_eq "1m40s" "$(dur 100)"
  assert_eq "60m00s" "$(dur 3600)"
}

test_devbox_locale_keeps_utf8_and_falls_back_to_C_UTF8() {
  helpers
  assert_eq "de_DE.UTF-8" "$(devbox_locale de_DE.UTF-8)"
  assert_eq "en_US.utf8" "$(devbox_locale en_US.utf8)"
  assert_eq "de_DE.UTF-8" "$(devbox_locale de_DE.UTF-8@euro)" "the @modifier is stripped"
  assert_eq "C.UTF-8" "$(devbox_locale POSIX)"
  assert_eq "C.UTF-8" "$(devbox_locale fr_FR.ISO-8859-1)" "a non-UTF-8 wish falls back"
  assert_eq "C.UTF-8" "$(devbox_locale "")"
}

test_debian_php_branch_per_release() {
  helpers
  assert_eq "8.2" "$(debian_php_branch 12)"
  assert_eq "8.4" "$(debian_php_branch 13)"
  assert_eq "8.5" "$(debian_php_branch 14)"
  assert_eq "" "$(debian_php_branch 11)" "unknown releases purge nothing"
}

test_run_quiet_hides_output_and_keeps_the_exit_status() {
  helpers
  V=0
  t_run run "build thing" bash -c 'echo noisy; exit 3'
  assert_status 3
  assert_contains "$T_OUT" "▸ build thing"
  assert_contains "$T_OUT" "✗ build thing"
  assert_not_contains "$T_OUT" "noisy"
}

test_run_verbose_streams_output_through_narrate() {
  helpers
  V=1
  t_run run "say hi" bash -c 'echo hello from the step'
  assert_status 0
  assert_contains "$T_OUT" "│${RST} hello from the step"
  assert_contains "$T_OUT" "✓"
}

test_narrate_drops_traces_blank_lines_and_repeats() {
  helpers
  local out
  out="$(printf '+ set -x trace\nkept\nkept\n\n++ nested trace\nalso kept\n' | narrate)"
  assert_eq 2 "$(grep -c 'kept' <<<"$out")" "one 'kept' line and one 'also kept' line"
  assert_not_contains "$out" "trace"
}

test_refuses_to_run_outside_root() {
  ((EUID != 0)) || return 0   # the gate only exists for non-root callers
  t_run bash ../private_dot_config/distrobox/executable_provision-dev.sh
  assert_status 1
  assert_contains "$T_OUT" "must run as root inside the container"
}

t_main
