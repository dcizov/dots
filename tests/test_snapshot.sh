#!/usr/bin/env bash
# snapshot-fresh-install.sh (`ucli snapshot`): one snapshot when snapper,
# its root config and a btrfs root are all there, a note otherwise; snapshot
# #1's id is kept, the latest one is tracked separately.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

snap() { ( source ../private_dot_local/share/ucli/scripts/system/executable_snapshot-fresh-install.sh "$@" ); }

ready() {
  export UCLI_TEST_ROOT="$T_ROOT/root"
  mkdir -p "$UCLI_TEST_ROOT/etc/snapper/configs"; : >"$UCLI_TEST_ROOT/etc/snapper/configs/root"
  echo 0 >"$T_ROOT/next"
  stub snapper 'n=$(( $(cat "${T_CALLS%/*}/next") + 1 )); echo $n >"${T_CALLS%/*}/next"; echo $n'
  stub findmnt 'echo btrfs'
  stub limine-snapper-sync
}

test_a_snapshot_is_taken_and_numbered() {
  ready
  t_run snap "gnome Setup"
  assert_status 0
  assert_called "snapper --no-dbus -c root create --print-number --description gnome Setup --userdata important=yes"
  assert_contains "$T_OUT" "Created snapshot (1): gnome Setup"
  assert_called "limine-snapper-sync"
}

test_snapshot_one_is_kept_and_the_latest_tracked() {
  ready
  snap "Fresh Arch Linux Installation" >/dev/null
  snap "before debloat (gnome)" >/dev/null
  snap "before ucli uninstall" >/dev/null
  assert_eq 1 "$(cat "$UCLI_TEST_ROOT/etc/ucli/installation-snapshot")"
  assert_eq 3 "$(cat "$UCLI_TEST_ROOT/etc/ucli/last-snapshot")"
}

test_skips_say_why() {
  ready
  t_run snap --no-snapshot x
  assert_contains "$T_OUT" "snapshot skipped"
  UCLI_NO_SNAPSHOT=1 t_run snap x
  assert_contains "$T_OUT" "snapshot skipped"
  stub findmnt 'echo ext4'
  t_run snap x
  assert_contains "$T_OUT" "/ is not btrfs"
  rm "$UCLI_TEST_ROOT/etc/snapper/configs/root"
  t_run snap x
  assert_contains "$T_OUT" "no snapper root config"
  rm "$T_BIN/snapper"; t_minimal_path
  t_run snap x
  assert_contains "$T_OUT" "snapper is not installed"
  assert_not_called "snapper --no-dbus"
}

test_dry_run_and_arguments() {
  ready
  t_run snap --dry-run "a test"
  assert_contains "$T_OUT" "+ snapper --no-dbus -c root create --description a\\ test"
  assert_not_called "snapper --no-dbus"
  t_run snap --bogus
  assert_status 2
}

t_main
