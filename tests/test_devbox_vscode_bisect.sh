#!/usr/bin/env bash
# devbox-vscode-bisect.sh: probes each file of the `bash -l` chain over ssh and
# names the one that eats stdin, then proves the host-spawn guard fixes it.
# ssh is a stub that plays a box whose distrobox_profile.sh (and so
# /etc/profile) swallows stdin unless host-spawn is shadowed.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

bisect() { ( source ../private_dot_local/share/ucli/scripts/devbox/executable_devbox-vscode-bisect.sh "$@" ); }

# fake_box [fixed|broken] — "broken" means even the guard does not help.
fake_box() {
  stub ssh "shift; cmd=\"\$*\"; mode=${1:-fixed}
  case \"\$cmd\" in
    *'exec bash -l'*) echo HELLO ;;
    *\"bash -c '\"*)
      if [[ \$cmd == *distrobox_profile.sh* || \$cmd == *'. /etc/profile >'* ]] &&
         [[ \$mode == broken || \$cmd != *'host-spawn() { :; }'* ]]; then
        cat >/dev/null
      else
        cat
      fi ;;
    *'cat /etc/profile.d/distrobox_profile.sh'*) echo 'export PATH=\$(host-spawn --path)' ;;
    *'bash -lx'*) echo '+ host-spawn --path' ;;
  esac"
}

test_the_stdin_eater_is_named_and_the_others_survive() {
  fake_box
  t_run bisect
  assert_status 0
  assert_contains "$T_PLAIN" "bisecting the bash -l profile chain on dev"
  assert_contains "$T_PLAIN" "ATE STDIN  /etc/profile.d/distrobox_profile.sh"
  assert_contains "$T_PLAIN" "survived  /etc/profile.d/bash_completion.sh"
  assert_contains "$T_PLAIN" "survived  . \$HOME/.bashrc"
}

test_the_guard_is_proven_end_to_end() {
  fake_box
  t_run bisect
  assert_contains "$T_PLAIN" "host-spawn was the stdin eater -- the guard below fixes it"
  assert_contains "$T_PLAIN" "bash -l with guard -> [HELLO]"
  assert_contains "$T_PLAIN" "  export PATH=\$(host-spawn --path)"
  assert_contains "$T_PLAIN" "  + host-spawn --path"
}

test_a_chain_the_guard_does_not_fix_says_so() {
  fake_box broken
  t_run bisect
  assert_contains "$T_PLAIN" "still eaten -- the culprit is elsewhere"
}

test_the_ssh_host_is_an_argument() {
  fake_box
  t_run bisect devbox-2
  assert_contains "$T_PLAIN" "profile chain on devbox-2"
  assert_called "ssh devbox-2"
  assert_not_called "ssh dev "
}

t_main
