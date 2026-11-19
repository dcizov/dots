#!/usr/bin/env bash
# inventory.sh: the command-line and environment gates, each stopping before a
# manifest is written. Full captures (package scopes, checksums, overrides)
# run against real files in tests/test_backup.py.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

inventory() { ( source ../private_dot_local/share/ucli/scripts/inventory/executable_inventory.sh "$@" ); }

test_options_that_need_a_path() {
  t_run inventory --appimage
  assert_status 1
  assert_contains "$T_OUT" "--appimage needs a path"
  t_run inventory --exclude-path
  assert_contains "$T_OUT" "--exclude-path needs a path"
}

test_one_output_directory_and_known_options_only() {
  t_run inventory "$T_ROOT/a" "$T_ROOT/b"
  assert_status 1
  assert_contains "$T_OUT" "give at most one output directory"
  t_run inventory --compress
  assert_contains "$T_OUT" "unknown option: --compress"
  t_run inventory --help
  assert_status 0
  assert_contains "$T_OUT" "OUTPUT-DIR must not exist"
}

test_exclusions_must_be_absolute() {
  ((EUID != 0)) || return 0
  t_run inventory --exclude-path relative/dir "$T_ROOT/out"
  assert_status 1
  assert_contains "$T_OUT" "--exclude-path needs an absolute path below /: relative/dir"
}

test_pacman_is_required_and_an_existing_output_is_refused() {
  ((EUID != 0)) || return 0
  t_minimal_path
  t_run inventory "$T_ROOT/out"
  assert_status 1
  assert_contains "$T_OUT" "pacman is required"
  stub pacman; stub pacman-conf
  mkdir -p "$T_ROOT/out"
  t_run inventory "$T_ROOT/out"
  assert_status 1
  assert_contains "$T_OUT" "output already exists: $T_ROOT/out"
}

t_main
