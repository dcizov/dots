#!/usr/bin/env bash
# update.sh (`ucli update`): pacman, the AUR helper (never on the timer),
# Flatpaks, mise and the dev box, each step reported, a failure making the
# run exit 1 without stopping the rest.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

update() { ( source ../private_dot_local/share/ucli/scripts/system/executable_update.sh "$@" ); }

box() {
  t_minimal_path
  stub sudo '"$@"'; stub pacman; stub flatpak; stub mise
  stub getent "echo \"alice:x:1000:1000::$HOME:/bin/bash\""
}

test_every_step_runs_unattended_without_a_terminal() {
  box; stub paru
  t_run update --no-snapshot </dev/null
  assert_status 0
  assert_called "pacman -Syu --noconfirm"
  assert_called "paru -Sua --noconfirm"
  assert_called "flatpak update -y"
  assert_called "mise upgrade"
}

test_the_configured_helper_wins() {
  box; stub paru; stub shelly
  t_config_file packages.bash <<<'AUR_HELPER=""'
  t_config_file packages.local.bash <<<'AUR_HELPER="paru"'
  t_run update --no-snapshot </dev/null
  assert_called "paru -Sua"
  assert_not_called "shelly"
  rm "$HOME/.config/ucli/packages.local.bash"
  : >"$T_CALLS"
  t_run update --no-snapshot </dev/null
  assert_called "shelly upgrade aur --no-confirm"
}

test_the_scheduled_run_skips_the_aur_and_the_dev_box() {
  box; stub paru
  t_run update --scheduled --no-snapshot
  assert_status 0
  assert_not_called "paru"
  assert_contains "$T_PLAIN" "AUR: skipped (scheduled run"
  assert_contains "$T_PLAIN" "dev box: skipped (scheduled run)"
}

test_a_failed_step_fails_the_run_but_not_the_rest() {
  box
  stub pacman 'echo "error: failed to synchronize"; exit 1'
  t_run update --no-snapshot --level minimal </dev/null
  assert_status 1
  assert_contains "$T_PLAIN" "pacman: system upgrade (exit 1)"
  assert_contains "$T_OUT" "error: failed to synchronize"
  assert_called "flatpak update -y"
  assert_contains "$T_PLAIN" "done: something failed"
}

test_no_aur_helper_is_a_skip() {
  box
  t_run update --no-snapshot </dev/null
  assert_status 0
  assert_contains "$T_PLAIN" "AUR: skipped (no paru or shelly installed"
}

test_level_validation_never_hangs() {
  box
  t_run timeout 5 bash -c 'source ../private_dot_local/share/ucli/scripts/system/executable_update.sh --level'
  assert_status 2
  assert_contains "$T_OUT" "--level needs"
  t_run update --level loud
  assert_status 2
  t_run update --bogus
  assert_status 2
}

t_main
