#!/usr/bin/env bash
# setup-pacman.sh (`ucli setup-pacman`): Color uncommented and ILoveCandy
# added inside [options] only, with a backup, validated by pacman-conf, and
# nothing written when validation fails or on --status/--dry-run.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

pacman_setup() { ( source ../private_dot_local/share/ucli/scripts/system/executable_setup-pacman.sh "$@" ); }

CONF() { printf '%s' "$UCLI_ETC_ROOT/etc/pacman.conf"; }
machine() {
  export UCLI_ETC_ROOT="$T_ROOT/root"
  mkdir -p "$UCLI_ETC_ROOT/etc"
  printf '[options]\nHoldPkg = pacman glibc\n#Color\nParallelDownloads = 5\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n#Color\n' >"$(CONF)"
  stub pacman-conf 'exit 0'
}

test_options_are_set_inside_options_only() {
  machine
  t_run pacman_setup
  assert_status 0
  local conf; conf="$(cat "$(CONF)")"
  assert_contains "$(sed -n '1,/^\[core\]/p' <<<"$conf")" $'\nColor\n'
  assert_contains "$(sed -n '1,/^\[core\]/p' <<<"$conf")" "ILoveCandy"
  assert_eq "#Color" "$(tail -1 <<<"$conf")" "a #Color outside [options] is not touched"
  local backups=("$(CONF)".bak-*)
  [[ -f "${backups[0]}" ]] || t_die "no timestamped backup was kept"
  assert_contains "$(cat "${backups[0]}")" "#Color"
}

test_already_set_is_a_no_op_and_status_reports() {
  machine
  pacman_setup >/dev/null 2>&1
  t_run pacman_setup
  assert_contains "$T_OUT" "already set"
  t_run pacman_setup --status
  assert_contains "$T_OUT" "Color:"
  assert_contains "$T_OUT" "nothing to do."
}

test_a_config_pacman_conf_rejects_is_not_kept() {
  machine
  cp "$(CONF)" "$T_ROOT/before"
  stub pacman-conf 'exit 1'
  t_run pacman_setup
  assert_status 1
  assert_eq "$(cat "$T_ROOT/before")" "$(cat "$(CONF)")"
}

test_dry_run_and_status_write_nothing() {
  machine
  cp "$(CONF)" "$T_ROOT/before"
  t_run pacman_setup --dry-run
  assert_status 0
  t_run pacman_setup --status
  assert_contains "$T_OUT" "commented out"
  assert_contains "$T_OUT" "apply with: sudo ucli setup-pacman"
  assert_eq "$(cat "$T_ROOT/before")" "$(cat "$(CONF)")"
}

test_no_pacman_conf_or_options_section() {
  machine
  rm "$(CONF)"
  t_run pacman_setup
  assert_status 1
  assert_contains "$T_OUT" "this is not an Arch-family machine"
  printf '[core]\nInclude = x\n' >"$(CONF)"
  t_run pacman_setup
  [[ "$T_STATUS" != 0 ]] || t_die "a pacman.conf without [options] must not be accepted"
  t_run pacman_setup --bogus
  assert_status 2
}

t_main
