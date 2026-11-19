#!/usr/bin/env bash
# install-dev-profile.sh (`ucli devmode`): the item catalogue, --all for
# non-interactive runs, fatal vs best-effort steps, the marker that merges
# picks across runs, and --status / --reset.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

devmode() { ( source ../private_dot_local/share/ucli/scripts/install/executable_install-dev-profile.sh "$@" ); }

MARKER() { printf '%s' "$XDG_STATE_HOME/ucli/devmode"; }

# siblings — the deployed script plus fakes for every step it runs.
siblings() {
  S="$(t_deployed install/install-dev-profile)"
  local d="${S%/*}" f
  for f in install-packages enable-docker-access install-flatpaks install-vscodium-extensions install-firefox-policies; do
    t_fake_script "$d/$f.sh"
  done
  t_fake_script "$d/../devbox/devbox-reconcile.sh"
  stub sudo '"$@"'; stub codium; stub distrobox
}

test_a_run_without_a_terminal_installs_everything() {
  siblings
  t_run bash "$S" </dev/null
  assert_status 0
  assert_contains "$T_PLAIN" "installing every devmode item (non-interactive)"
  assert_called "install-packages.sh dev-cli"
  assert_called "install-packages.sh --force dev"
  assert_called "enable-docker-access.sh"
  assert_called "install-flatpaks.sh dev"
  assert_called "install-vscodium-extensions.sh"
  assert_called "install-firefox-policies.sh --dev"
  assert_called "devbox-reconcile.sh"
  assert_contains "$(cat "$(MARKER)")" "items=dev-cli,dev-pkgs,flatpaks,vscodium,firefox,devbox"
}

test_a_failed_core_step_stops_and_records_nothing() {
  siblings
  t_fake_script "${S%/*}/install-packages.sh" '[[ $1 != dev-cli ]]'
  t_run bash "$S" --all
  assert_status 1
  assert_contains "$T_PLAIN" "dev CLI packages failed; stopping."
  assert_not_called "install-flatpaks.sh"
  [[ ! -e "$(MARKER)" ]] || t_die "a stopped run must not write the marker"
}

test_a_failed_optional_step_continues_and_names_it() {
  siblings
  t_fake_script "${S%/*}/install-flatpaks.sh" 'exit 1'
  t_fake_script "${S%/*}/install-vscodium-extensions.sh" 'exit 1'
  t_run bash "$S" --all
  assert_status 1
  assert_called "devbox-reconcile.sh"
  assert_contains "$T_PLAIN" "Re-run 'ucli devmode' to retry: dev flatpaks, VSCodium extensions"
  assert_contains "$(cat "$(MARKER)")" "items=dev-cli,dev-pkgs,firefox,devbox"
}

test_missing_codium_or_distrobox_skips_instead_of_failing() {
  siblings
  rm "$T_BIN/codium" "$T_BIN/distrobox"
  t_minimal_path
  stub sudo '"$@"'
  t_run bash "$S" --all
  assert_status 0
  assert_contains "$T_OUT" "skipped: codium is not installed"
  assert_contains "$T_OUT" "skipped: distrobox is not installed"
  assert_not_called "devbox-reconcile.sh"
}

test_a_later_run_keeps_the_earlier_picks() {
  mkdir -p "$XDG_STATE_HOME/ucli"
  printf 'version=1\nitems=devbox\nupdated=then\n' >"$(MARKER)"
  siblings
  t_run bash "$S" --all
  assert_contains "$T_PLAIN" "Developer mode is already set up."
  assert_contains "$(cat "$(MARKER)")" "items=devbox,dev-cli,dev-pkgs,flatpaks,vscodium,firefox"
}

test_status_and_reset() {
  t_run devmode --status
  assert_status 0
  assert_contains "$T_OUT" "devmode: not configured"
  mkdir -p "$XDG_STATE_HOME/ucli"
  printf 'version=1\nitems=dev-cli\n' >"$(MARKER)"
  t_run devmode --status
  assert_contains "$T_OUT" "  items=dev-cli"
  t_run devmode --reset
  assert_status 0
  assert_no_file "$(MARKER)"
}

test_arguments() {
  t_run devmode --bogus
  assert_status 2
  t_run devmode --help
  assert_contains "$T_OUT" "install-dev-profile.sh --all"
}

t_main
