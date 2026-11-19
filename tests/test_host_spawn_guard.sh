#!/usr/bin/env bash
# 00-host-spawn-guard.sh: non-interactive login shells get a no-op host-spawn
# function (so the wrapper cannot steal stdin from scp/rsync/Remote-SSH),
# interactive ones keep the real command, and plain sh parses it unharmed.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

GUARD=../private_dot_config/distrobox/files/00-host-spawn-guard.sh

test_non_interactive_bash_gets_a_no_op_function() {
  stub host-spawn 'cat >/dev/null; echo "the real host-spawn ran"'
  source ../private_dot_config/distrobox/files/00-host-spawn-guard.sh
  assert_eq "function" "$(type -t host-spawn)"
  # the function must not read stdin: what is piped in stays for the next reader
  assert_eq "payload" "$( { host-spawn; cat; } <<<"payload")"
  assert_not_called "host-spawn"
}

test_interactive_bash_keeps_the_real_command() {
  stub host-spawn
  t_run bash --norc -i -c ". '$GUARD'; type -t host-spawn"
  assert_contains "$T_OUT" "file"
  assert_not_contains "$T_OUT" "function"
}

test_zsh_non_interactive_gets_the_function_too() {
  command -v zsh >/dev/null 2>&1 || return 0
  t_run zsh -f -c ". '$GUARD'; whence -w host-spawn"
  assert_status 0
  assert_eq "host-spawn: function" "$T_OUT"
}

test_posix_sh_parses_it_and_defines_nothing() {
  local sh
  for sh in dash sh; do
    command -v "$sh" >/dev/null 2>&1 || continue
    t_run "$sh" -c ". '$GUARD'; command -v host-spawn || echo none"
    assert_status 0
    # bash-as-sh still sets BASH_VERSION and so takes the function branch;
    # a real POSIX sh must simply define nothing.
    if [[ "$sh" == dash ]]; then assert_eq "none" "$T_OUT"; fi
  done
}

t_main
