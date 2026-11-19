#!/usr/bin/env bash
# backup-home.sh: the command-line and configuration gates, each of which must
# stop before restic runs. The backup itself (init, run, manifests, mounts) is
# exercised against a real temporary restic repository by tests/test_backup.py.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

backup() { ( source ../private_dot_local/share/ucli/scripts/backup/executable_backup-home.sh "$@" ); }

UUID="096a9598-b488-4d51-8d14-e592387e1338"

setup() {
  stub restic
  mkdir -p "$T_ROOT/repo"
}

config() {
  t_config_file backup.local.bash
}

test_no_arguments_prints_usage() {
  setup
  t_run backup
  assert_status 0
  assert_contains "$T_OUT" "usage: ucli backup preflight|init|run|snapshots|check"
}

test_an_unknown_action_is_a_usage_error() {
  setup
  t_run backup restore
  assert_status 2
  assert_contains "$T_OUT" "usage: ucli backup"
  assert_not_called "restic"
}

test_only_run_takes_options() {
  setup
  local action
  for action in preflight init snapshots check; do
    t_run backup "$action" --dry-run
    assert_status 1
    assert_contains "$T_OUT" "$action does not take extra arguments"
  done
  t_run backup run --compress
  assert_status 1
  assert_contains "$T_OUT" "unknown option: --compress"
  t_run backup run --tag "bad tag"
  assert_contains "$T_OUT" "--tag needs a name"
  assert_not_called "restic"
}

test_a_missing_config_points_at_the_example() {
  ((EUID != 0)) || return 0
  setup
  t_run backup preflight
  assert_status 1
  assert_contains "$T_OUT" "set up $HOME/.config/ucli/backup.local.bash using backup.local.bash.example"
  assert_not_called "restic"
}

test_the_uuid_must_be_a_filesystem_uuid() {
  ((EUID != 0)) || return 0
  setup
  printf 'BACKUP_REPO=%q\nBACKUP_UUID=%q\n' "$T_ROOT/repo" "PARTUUID-1234" | config
  t_run backup preflight
  assert_status 1
  assert_contains "$T_OUT" "set BACKUP_UUID to the known ext4 filesystem UUID"
  assert_not_called "restic"
}

test_an_unmounted_repository_is_reported_as_such() {
  ((EUID != 0)) || return 0
  setup
  printf 'BACKUP_REPO=%q\nBACKUP_UUID=%q\n' "$T_ROOT/not-mounted" "$UUID" | config
  t_run backup snapshots
  assert_status 1
  assert_contains "$T_OUT" "repository directory is missing: $T_ROOT/not-mounted (is the drive mounted?)"
  assert_not_called "restic"
}

test_UCLI_BACKUP_CONFIG_overrides_the_default_path() {
  ((EUID != 0)) || return 0
  setup
  export UCLI_BACKUP_CONFIG="$T_ROOT/elsewhere.bash"
  t_run backup check
  assert_contains "$T_OUT" "set up $T_ROOT/elsewhere.bash"
}

t_main
