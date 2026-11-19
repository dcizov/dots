#!/usr/bin/env bash
# ucli-menu.sh (`ucli` with no arguments): without a terminal it prints the
# plain recipe list instead of a menu nobody can answer; it needs just and a
# justfile. The interactive gum menu itself is not driven here.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

menu() { ( source ../private_dot_local/share/ucli/scripts/system/executable_ucli-menu.sh "$@" ); }

justfile() {
  export UCLI_JUSTFILE="$T_ROOT/ucli/justfile"
  mkdir -p "$T_ROOT/ucli"
  printf "[group('Fix')]\nfix-lock:\n    @echo FIXED\n\n# install the cli\n[group('Install')]\ncli:\n    @echo CLI\n" >"$UCLI_JUSTFILE"
}

test_without_a_terminal_it_lists_every_recipe() {
  command -v just >/dev/null 2>&1 || return 0
  justfile
  t_run menu </dev/null
  assert_status 0
  assert_contains "$T_OUT" "[Fix]"
  assert_contains "$T_OUT" "fix-lock"
  assert_contains "$T_OUT" "cli      # install the cli"
}

test_it_needs_just_and_a_justfile() {
  t_minimal_path
  justfile
  t_run menu
  assert_status 1
  assert_contains "$T_OUT" "just is not installed"
  stub just
  export UCLI_JUSTFILE="$T_ROOT/nowhere/justfile"
  t_run menu
  assert_status 1
  assert_contains "$T_OUT" "no justfile at $T_ROOT/nowhere/justfile"
}

test_the_real_justfile_parses_into_groups() {
  command -v just >/dev/null 2>&1 || return 0
  UCLI_JUSTFILE="$(cd ../private_dot_config/ucli && pwd)/justfile"
  export UCLI_JUSTFILE
  t_run menu </dev/null
  assert_status 0
  local g
  for g in Install System Fix Help; do assert_contains "$T_OUT" "[$g]"; done
}

t_main
