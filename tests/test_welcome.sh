#!/usr/bin/env bash
# welcome.sh (`ucli welcome`, and the lines above `ucli`'s menu): machine,
# repo, pending updates, last snapshot, reboot; the tweak count; next steps;
# and the first-login screen exactly once.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

welcome() { ( source ../private_dot_local/share/ucli/scripts/system/executable_welcome.sh "$@" ); }

box() {
  export USER=alice
  mkdir -p "$HOME/.local/share/chezmoi"
  stub git 'echo "abc1234 fix(something): words"'
  stub pacman '[[ $1 == -Qu ]] && printf "linux 6.1 -> 6.2\nmesa 1 -> 2\n"; exit 0'
  stub systemctl '[[ $3 == bluetooth.service ]]'
  t_config_file packages.bash <<<'TWEAKS=("bluetooth|bluetooth.service|bluez|system|BT" "cups|cups.service|cups|system|Print")'
}

test_status_names_the_repo_and_pending_updates() {
  box
  export XDG_CURRENT_DESKTOP=GNOME
  t_run welcome --status
  assert_status 0
  assert_contains "$T_OUT" "GNOME · repo abc1234"
  if [[ -r /var/lib/pacman/local ]]; then
    assert_contains "$T_OUT" "2 package update(s)"
  fi
  assert_contains "$T_OUT" "snapshot"
}

test_full_counts_tweaks_including_the_overlay() {
  box
  t_run welcome
  assert_contains "$T_OUT" "1/2 enabled"
  t_config_file packages.local.bash <<<'TWEAKS=("bluetooth|bluetooth.service|bluez|system|BT")'
  t_run welcome
  assert_contains "$T_OUT" "1/1 enabled"
  assert_contains "$T_OUT" "ucli setup-system gnome — no desktop session yet"
  assert_contains "$T_OUT" "ucli devmode — optional developer tooling"
}

test_first_login_shows_once() {
  box
  t_run welcome --first-login
  assert_contains "$T_PLAIN" "welcome"
  t_run welcome --first-login
  assert_eq "" "$T_OUT"
}

test_no_repo_points_at_the_bootstrap() {
  box
  rm -r "$HOME/.local/share/chezmoi"
  stub git 'exit 1'
  t_run welcome
  assert_contains "$T_OUT" "repo not deployed"
  assert_contains "$T_OUT" "bootstrap — the repo is not deployed yet"
  t_run welcome --bogus
  assert_status 2
}

t_main
