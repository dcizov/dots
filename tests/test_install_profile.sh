#!/usr/bin/env bash
# install-profile.sh (`ucli setup-system`): the order of the machine steps,
# which failures stop the run (packages, flatpaks, desktop) and which only
# warn (pacman.conf, boot splash), and the flags handed down.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

profile() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-profile.sh "$@" ); }

steps() {
  S="$(t_deployed install/install-profile)"
  local d="${S%/*}" s
  for s in install-packages install-flatpaks setup-desktop; do t_fake_script "$d/$s.sh"; done
  for s in snapshot-fresh-install setup-pacman setup-boot; do t_fake_script "$d/../system/$s.sh"; done
  stub sudo '"$@"'
  export UCLI_ETC_ROOT="$T_ROOT/root"
  mkdir -p "$UCLI_ETC_ROOT/etc/snapper/configs"
  : >"$UCLI_ETC_ROOT/etc/snapper/configs/root"
}
order() { awk '$1 != "sudo" {print $1}' "$T_CALLS" | tr '\n' ' '; }

test_the_steps_run_in_order_with_their_flags() {
  steps
  t_run bash "$S" gnome --force
  assert_status 0
  assert_eq "snapshot-fresh-install.sh install-packages.sh setup-pacman.sh install-flatpaks.sh setup-desktop.sh setup-boot.sh " "$(order)"
  assert_called "snapshot-fresh-install.sh before setup-system"
  assert_called "install-packages.sh base"
  assert_called "install-flatpaks.sh base"
  assert_called "setup-desktop.sh gnome --force"
  assert_called "setup-boot.sh --yes"
}

test_no_snapshot_reaches_every_snapshotting_step() {
  steps
  t_run bash "$S" --no-snapshot kde
  assert_called "snapshot-fresh-install.sh --no-snapshot before setup-system"
  assert_called "setup-desktop.sh kde --no-snapshot"
}

test_a_failing_core_step_stops_with_its_name() {
  steps
  t_fake_script "${S%/*}/install-flatpaks.sh" 'exit 4'
  t_run bash "$S" hyprland
  assert_status 4
  assert_contains "$T_PLAIN" "base flatpaks failed (exit 4)"
  assert_contains "$T_PLAIN" "re-run: ucli setup-system hyprland"
  assert_not_called "setup-desktop.sh"
}

test_advisory_steps_only_warn() {
  steps
  t_fake_script "${S%/*}/../system/setup-pacman.sh" 'exit 1'
  t_fake_script "${S%/*}/../system/setup-boot.sh" 'exit 1'
  t_run bash "$S"
  assert_status 0
  assert_contains "$T_PLAIN" "retry later: sudo ucli setup-pacman"
  assert_contains "$T_PLAIN" "boot splash not configured"
  assert_contains "$T_PLAIN" "setup-system done"
}

test_without_snapper_it_warns_and_proceeds_off_a_terminal() {
  steps
  rm "$UCLI_ETC_ROOT/etc/snapper/configs/root"
  t_run bash "$S" </dev/null
  assert_status 0
  assert_contains "$T_PLAIN" "no Snapper config found"
  assert_called "install-packages.sh base"
}

test_arguments() {
  t_run profile --bogus
  assert_status 2
  t_run profile --help
  assert_contains "$T_OUT" "usage: install-profile.sh"
}

t_main
