#!/usr/bin/env bash
# update-timer.sh (`ucli update-timer`): writes ucli-update.service/.timer
# (daily or HH:MM), enables them, removes them again, and reports their state.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

timer() { ( source ../private_dot_local/share/ucli/scripts/system/executable_update-timer.sh "$@" ); }

UNITS() { printf '%s' "$UCLI_TEST_ROOT/etc/systemd/system"; }
box() {
  export UCLI_TEST_ROOT="$T_ROOT/root" USER=alice
  mkdir -p "$HOME/.local/share/ucli/scripts/system"
  printf '#!/bin/sh\n' >"$HOME/.local/share/ucli/scripts/system/update.sh"
  chmod +x "$HOME/.local/share/ucli/scripts/system/update.sh"
  stub systemctl "case \$1 in is-enabled) ${FAKE_STATE:-echo disabled; exit 1} ;; esac; exit 0"
}

test_on_writes_both_units_and_enables_the_timer() {
  box
  t_run timer on --time 03:30
  assert_status 0
  assert_contains "$(cat "$(UNITS)/ucli-update.timer")" "OnCalendar=*-*-* 03:30:00"
  assert_contains "$(cat "$(UNITS)/ucli-update.service")" "ExecStart=$HOME/.local/share/ucli/scripts/system/update.sh --scheduled"
  assert_contains "$(cat "$(UNITS)/ucli-update.service")" "Environment=UCLI_TIMER_USER=alice"
  assert_called "systemctl daemon-reload"
  assert_called "systemctl enable --now ucli-update.timer"
}

test_off_removes_them_and_is_a_no_op_twice() {
  box
  timer on >/dev/null 2>&1
  t_run timer off
  assert_called "systemctl disable --now ucli-update.timer"
  assert_no_file "$(UNITS)/ucli-update.timer"
  stub systemctl 'exit 1'
  t_run timer off
  assert_contains "$T_OUT" "not installed — nothing to do"
}

test_status_tells_disabled_from_missing() {
  box
  t_run timer status
  assert_contains "$T_OUT" "state:   disabled"
  stub systemctl 'exit 1'
  t_run timer status
  assert_contains "$T_OUT" "state:   not installed"
  mkdir -p "$(UNITS)"; : >"$(UNITS)/ucli-update.timer"
  t_run timer status
  assert_contains "$T_OUT" "state:   installed, not enabled"
}

test_dry_run_and_validation() {
  box
  t_run timer on --dry-run
  assert_contains "$T_OUT" "OnCalendar=daily"
  assert_no_file "$(UNITS)/ucli-update.timer"
  t_run timer on --time 25:00
  assert_status 2
  t_run timer on --time
  assert_status 2
  assert_contains "$T_OUT" "--time needs daily or HH:MM"
  rm "$HOME/.local/share/ucli/scripts/system/update.sh"
  t_run timer on
  assert_status 1
  assert_contains "$T_OUT" "run the bootstrap"
}

t_main
