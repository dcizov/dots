#!/usr/bin/env bash
# devbox-vscode-doctor.sh: walks ssh auth -> login shell -> plain exec -> the
# extension's `base64 -d | bash -l` pipeline and names the first broken layer.
# ssh is a stub whose box is steered by FAKE_* variables.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

vdoctor() { ( source ../private_dot_local/share/ucli/scripts/devbox/executable_devbox-vscode-doctor.sh "$@" ); }

# FAKE_AUTH=0 refuses the connection, FAKE_SHELL is the passwd shell and
# FAKE_SHELL_OK=0 makes it missing, FAKE_LOGIN=0 breaks `bash -l` on stdin,
# FAKE_BASH=0 breaks plain bash too.
fake_box() {
  stub ssh '[[ $1 == -o ]] && shift 4; shift; cmd="$*"
  case "$cmd" in
    true)              [[ ${FAKE_AUTH:-1} == 1 ]] || { echo "Permission denied (publickey)." >&2; exit 255; } ;;
    *getent*)          echo "${FAKE_SHELL:-/bin/bash}" ;;
    "[ -x "*)          [[ ${FAKE_SHELL_OK:-1} == 1 ]]; exit ;;
    "uname -s")        echo Linux ;;
    *"| bash -l")      [[ ${FAKE_LOGIN:-1} == 1 ]] && echo HELLO ;;
    *"| bash")         [[ ${FAKE_BASH:-1} == 1 ]] && echo HELLO ;;
  esac; exit 0'
}

test_failed_auth_stops_at_layer_one() {
  fake_box
  export FAKE_AUTH=0
  t_run vdoctor
  assert_status 1
  assert_contains "$T_PLAIN" "FAIL  ssh dev true"
  assert_contains "$T_PLAIN" "Permission denied (publickey)."
  assert_contains "$T_PLAIN" "Stop here"
  assert_not_contains "$T_PLAIN" "2. login shell"
}

test_a_healthy_box_passes_every_layer() {
  fake_box
  t_run vdoctor
  assert_status 0
  assert_contains "$T_PLAIN" "PASS  ssh dev true"
  assert_contains "$T_PLAIN" "PASS  /bin/bash exists and is executable in the box"
  assert_contains "$T_PLAIN" "PASS  uname -s -> Linux"
  assert_contains "$T_PLAIN" "PASS  login bash runs a piped script correctly"
  assert_contains "$T_PLAIN" "== done =="
  assert_called "ssh -o BatchMode=yes -o ConnectTimeout=5 dev true"
}

test_a_host_shell_missing_in_the_box_is_named() {
  fake_box
  export FAKE_SHELL=/usr/bin/zsh FAKE_SHELL_OK=0
  t_run vdoctor
  assert_contains "$T_PLAIN" "FAIL  /usr/bin/zsh is missing or not executable in the box"
  assert_contains "$T_PLAIN" "install zsh in the box or point the entry at /bin/bash"
}

test_a_broken_login_profile_is_the_root_cause() {
  fake_box
  export FAKE_LOGIN=0
  t_run vdoctor
  assert_contains "$T_PLAIN" "with    -l  -> []"
  assert_contains "$T_PLAIN" "without -l  -> [HELLO]"
  assert_contains "$T_PLAIN" "\`bash -l\` is the broken layer"
}

test_when_even_plain_bash_fails_the_pipeline_is_blamed() {
  fake_box
  export FAKE_LOGIN=0 FAKE_BASH=0
  t_run vdoctor
  assert_contains "$T_PLAIN" "even plain \`bash\` produces nothing"
}

test_the_host_is_an_argument() {
  fake_box
  t_run vdoctor devbox-2
  assert_contains "$T_PLAIN" "== target: ssh devbox-2 =="
  assert_called "ConnectTimeout=5 devbox-2 true"
}

t_main
