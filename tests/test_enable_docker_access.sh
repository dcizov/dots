#!/usr/bin/env bash
# enable-docker-access.sh: enable + start docker.service and put the invoking
# user in the docker group, each only when needed; --status reports both.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

grant() { ( source ../private_dot_local/share/ucli/scripts/install/executable_enable-docker-access.sh "$@" ); }

# world <enabled 0|1> <running 0|1> <member 0|1>
world() {
  stub docker
  stub sudo '"$@"'
  stub usermod
  stub systemctl "case \$1 in
    is-enabled) exit $((1 - $1)) ;;
    is-active)  exit $((1 - $2)) ;;
  esac"
  stub id "[[ \$1 == -nG ]] && { [[ $3 == 1 ]] && echo 'wheel docker' || echo wheel; }; exit 0"
  export USER=alice
}

test_a_fresh_install_gets_the_service_and_the_group() {
  world 0 0 0
  t_run grant
  assert_status 0
  assert_called "systemctl enable --now docker.service"
  assert_called "usermod -aG docker alice"
  assert_contains "$T_OUT" "Log out and back in (or run: newgrp docker)"
}

test_an_already_granted_machine_changes_nothing() {
  world 1 1 1
  t_run grant
  assert_status 0
  assert_contains "$T_OUT" "already enabled and running"
  assert_contains "$T_OUT" "alice is already a member"
  assert_not_called "systemctl enable"
  assert_not_called "usermod"
}

test_an_enabled_but_stopped_service_is_started() {
  world 1 0 1
  t_run grant
  assert_called "systemctl enable --now docker.service"
}

test_no_service_only_grants_the_group() {
  world 0 0 0
  t_run grant --no-service
  assert_not_called "systemctl enable"
  assert_called "usermod -aG docker alice"
}

test_under_sudo_the_invoking_user_is_granted() {
  world 1 1 0
  export SUDO_USER=bob
  t_run grant
  assert_called "usermod -aG docker bob"
}

test_status_reports_without_changing_anything() {
  world 1 0 0
  t_run grant --status
  assert_status 0
  assert_contains "$T_OUT" "docker.service : enabled / stopped"
  assert_contains "$T_OUT" "docker group   : alice is NOT a member"
  assert_not_called "usermod"
  assert_not_called "systemctl enable"
}

test_without_docker_there_is_nothing_to_grant() {
  t_minimal_path
  t_run grant
  assert_status 0
  assert_contains "$T_OUT" "docker is not installed; nothing to grant"
}

test_arguments() {
  t_run grant --bogus
  assert_status 2
  t_run grant --help
  assert_contains "$T_OUT" "Usage: enable-docker-access.sh [--no-service] [--status]"
}

t_main
