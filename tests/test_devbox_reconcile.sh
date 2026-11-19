#!/usr/bin/env bash
# devbox-reconcile.sh: everything that is decided before a container is touched
# — arguments, the per-user lock, dev.ini parsing, the container manager, the
# --exists answer and the provisioner check. Creating and provisioning a real
# box needs podman and is not exercised here.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

SCRIPT=../private_dot_local/share/ucli/scripts/devbox/executable_devbox-reconcile.sh
reconcile() { ( source ../private_dot_local/share/ucli/scripts/devbox/executable_devbox-reconcile.sh "$@" ); }

# box <inspect-ok 0|1> <running 0|1> — distrobox and podman stubs, dev.ini with
# a [dev] section on debian:12, and the lock already held.
box() {
  t_minimal_path
  export DEVBOX_LOCKED=1
  unset DISTROBOX_CONTAINER_MANAGER
  stub distrobox
  stub podman "case \$1 in
    inspect) exit $((1 - ${1:-1})) ;;
    ps) [[ ${2:-1} == 1 ]] && echo 0123abcd ;;
  esac; exit 0"
  mkdir -p "$HOME/.config/distrobox"
  printf '[dev]\nimage=debian:12\n' >"$HOME/.config/distrobox/dev.ini"
}

test_arguments() {
  t_run reconcile --bogus
  assert_status 2
  assert_contains "$T_OUT" "unknown argument: --bogus"
  t_run reconcile --help
  assert_status 0
  assert_contains "$T_OUT" "devbox-reconcile.sh --exists"
}

test_without_distrobox_a_run_is_skipped_and_exists_says_no() {
  t_minimal_path
  t_run reconcile
  assert_status 0
  assert_contains "$T_OUT" "distrobox not installed — skipping"
  t_run reconcile --exists
  assert_status 1
  assert_eq "" "$T_OUT" "--exists prints nothing"
}

test_a_run_takes_the_lock_by_re_executing_itself_under_flock() {
  box
  unset DEVBOX_LOCKED
  stub flock
  t_run reconcile --quiet
  assert_status 0
  assert_called "flock -w 900 $HOME/.local/state/distrobox-dev.lock $SCRIPT --quiet"
}

test_exists_answers_running_stopped_or_absent() {
  box 1 1; t_run reconcile --exists; assert_status 0
  box 1 0; t_run reconcile --exists; assert_status 3
  box 0 0; t_run reconcile --exists; assert_status 1
  assert_eq "" "$T_OUT"
}

test_dev_ini_must_exist_and_name_a_box() {
  box
  rm "$HOME/.config/distrobox/dev.ini"
  t_run reconcile
  assert_status 1
  assert_contains "$T_OUT" "missing $HOME/.config/distrobox/dev.ini (run 'chezmoi apply' first)"
  echo 'image=debian:12' >"$HOME/.config/distrobox/dev.ini"
  t_run reconcile
  assert_status 1
  assert_contains "$T_OUT" "no [section] found"
}

test_the_container_manager_comes_from_distrobox_conf() {
  box
  stub docker 'exit 1'
  echo 'container_manager="docker"' >"$HOME/.config/distrobox/distrobox.conf"
  t_run reconcile --exists
  assert_status 1
  assert_called "docker inspect dev"
  assert_not_called "podman"
}

test_a_configured_manager_that_is_missing_is_an_error() {
  box
  export DISTROBOX_CONTAINER_MANAGER=lilipod
  t_run reconcile
  assert_status 1
  assert_contains "$T_OUT" "container manager 'lilipod' (from distrobox config) not found"
}

test_a_missing_provisioner_stops_before_the_box_is_touched() {
  box
  t_run reconcile
  assert_status 1
  assert_contains "$T_OUT" "missing $HOME/.config/distrobox/provision-dev.sh"
  assert_not_called "podman start"
  assert_not_called "distrobox"
}

t_main
