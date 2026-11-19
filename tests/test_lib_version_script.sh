#!/usr/bin/env bash
# lib/version-script.sh: a step runs until its token is committed, runs again
# when the token changes, and can be forgotten; gates live in XDG_STATE_HOME.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

vs() { source ../private_dot_local/share/ucli/scripts/lib/version-script.sh; }

test_a_gate_opens_until_committed_and_reopens_on_a_new_token() {
  vs
  vs_check demo user 1 || t_die "never committed: must run"
  vs_commit demo user 1
  ! vs_check demo user 1 || t_die "committed: must not run"
  vs_check demo user 2 || t_die "new token: must run again"
  assert_eq 1 "$(vs_current demo user)"
  assert_file "$XDG_STATE_HOME/ucli/gates/user/demo"
}

test_forget_and_list() {
  vs
  vs_commit alpha user abc
  vs_commit beta system 7
  assert_eq $'system\tbeta\t7\nuser\talpha\tabc' "$(vs_list)"
  vs_forget alpha user
  vs_check alpha user abc || t_die "forgotten gate must run"
}

test_hash_follows_content() {
  vs
  echo one >"$T_ROOT/f"
  local a b; a="$(vs_hash "$T_ROOT/f")"
  echo two >"$T_ROOT/f"; b="$(vs_hash "$T_ROOT/f")"
  [[ "$a" != "$b" && ${#a} -eq 12 ]] || t_die "hash must change with the content: $a $b"
  echo one >"$T_ROOT/f"
  assert_eq "$a" "$(vs_hash "$T_ROOT/f")"
}

test_a_relative_state_home_falls_back_to_home() {
  vs
  export XDG_STATE_HOME=relative/state
  assert_eq "$HOME/.local/state/ucli/gates/user" "$(vs_state_dir user)"
}

t_main
