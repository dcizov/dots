#!/usr/bin/env bash
# lib/ui.sh without a terminal (as in CI and pipes): plain output, steps that
# report their command's status, links spelled out, and menus/confirmations
# that decline rather than hang.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

ui() { source ../private_dot_local/share/ucli/scripts/lib/ui.sh; }

test_ok_and_fail_lines() {
  ui
  assert_contains "$(ui_ok "all good" 2>&1)" "✓ all good"
  assert_contains "$(ui_fail broke 2>&1)" "broke"
}

test_a_step_reports_its_commands_status() {
  ui
  t_run ui_step 0 3 "first" -- true
  assert_status 0
  assert_contains "$T_OUT" "1/3] first"
  assert_contains "$T_OUT" "✓ first"
  t_run ui_step 1 3 "second" -- false
  assert_status 1
  assert_contains "$T_OUT" "second"
}

test_links_are_spelled_out_without_a_terminal() {
  ui
  assert_eq "docs (https://example.org)" "$(ui_link https://example.org docs)"
  assert_eq "https://example.org" "$(ui_link https://example.org)"
}

test_menus_and_confirmations_decline_without_a_terminal() {
  ui
  ! ui_confirm "really?" </dev/null || t_die "confirm said yes with no terminal"
  ! ui_choose_multi "pick" a b </dev/null >/dev/null || t_die "a menu answered with no terminal"
  ! ui_choose_multi "pick" </dev/null >/dev/null || t_die "an empty menu answered"
}

t_main
