#!/usr/bin/env bash
# install-vscodium-extensions.sh: every id in extensions.txt goes through
# `codium --install-extension`, gated on the list's hash — and a run with a
# failed install is not remembered as done.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

codium_ext() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-vscodium-extensions.sh "$@" ); }

list() {
  mkdir -p "$HOME/.config/VSCodium/User"
  printf '# editor\nrust-lang.rust-analyzer\n  esbenp.prettier-vscode   # formatting\n\n' >"$HOME/.config/VSCodium/User/extensions.txt"
}

test_every_listed_extension_is_installed_once_per_list_version() {
  list; stub codium
  t_run codium_ext
  assert_status 0
  assert_called "codium --install-extension rust-lang.rust-analyzer"
  assert_called "codium --install-extension esbenp.prettier-vscode"
  assert_contains "$T_OUT" "2 extension entries processed"
  t_run codium_ext
  assert_contains "$T_OUT" "unchanged since the last run"
  t_run codium_ext --force
  assert_contains "$T_OUT" "2 extension entries processed"
}

test_a_failed_install_is_retried_next_time() {
  list; stub codium '[[ $2 != esbenp.prettier-vscode ]]'
  t_run codium_ext
  assert_status 1
  assert_contains "$T_OUT" "failed: esbenp.prettier-vscode"
  stub codium
  : >"$T_CALLS"
  t_run codium_ext
  assert_status 0
  assert_called "codium --install-extension esbenp.prettier-vscode"
}

test_missing_list_codium_and_bad_arguments() {
  t_minimal_path
  t_run codium_ext
  assert_status 1
  assert_contains "$T_OUT" "extensions file not found"
  list
  t_run codium_ext
  assert_contains "$T_OUT" "'codium' not found on PATH"
  t_run codium_ext --bogus
  assert_status 2
}

t_main
